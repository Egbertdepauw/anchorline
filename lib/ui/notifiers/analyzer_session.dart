/// The analyzer connection and Log on OK, owned by the app shell so they
/// outlive the screen that shows them: the SOLO stays connected and an OK
/// press is still saved while the diver is on another tab.
///
/// Over a USB cable the session runs a [UsbOkLogger], which finds the OK
/// presses in the SOLO's stream, while Log on OK is on. Over the bridge the
/// bridge finds them itself and sends records: the session runs a
/// [BridgeOkHandler] for as long as it is on the bridge, whether Log on OK
/// is on or off, because waiting records are always collected (spec §4
/// "Records and sessions"), and a [BridgeStateReporter] for the bridge
/// screen. With Log on OK on, the handler is the save card's [OkLogger].
library;

import 'dart:async' show StreamSubscription, unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:sentry_flutter/sentry_flutter.dart' show Sentry;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../analyzer/analyzer_controller.dart';
import '../../analyzer/bridge/bridge_ok_handler.dart';
import '../../analyzer/bridge/bridge_protocol.dart' show BridgeMessage;
import '../../analyzer/bridge/bridge_state_reporter.dart';
import '../../analyzer/ok_record_processor.dart';
import '../../analyzer/transport/analyzer_transport.dart';
import '../../analyzer/transport/analyzer_transport_options.dart';
import '../../analyzer/transport/ble_bridge_transport.dart';
import '../../analyzer/usb_ok_logger.dart';
import '../../data/db/gas_analyses_dao.dart';
import '../../data/db/open_blends_dao.dart';
import '../../label_printer/label_printer.dart' show LabelPrinterException;
import '../../labels/label_print_service.dart';
import '../widgets/analyzer/bridge_transport_option.dart';
import 'settings_notifier.dart';

class AnalyzerSession extends ChangeNotifier {
  AnalyzerSession({
    required SettingsNotifier settings,
    GasAnalysesDaoLike? analysesDao,
    LabelPrintService? labelPrinting,
    AnalyzerController? controller,
    List<AnalyzerTransportOption>? transportOptions,
    UsbOkLogger Function()? okLoggerFactory,
    Future<void> Function(bool awake)? keepAwake,
    OpenBlendsDaoLike? openBlends,
  })  : _settings = settings,
        _analysesDao = analysesDao,
        _labelPrinting = labelPrinting,
        _ownsController = controller == null,
        _controller = controller ?? AnalyzerController(),
        _options = transportOptions ??
            defaultAnalyzerTransportOptions(
              bridge: bridgeTransportOption(settings),
            ),
        _okLoggerFactory = okLoggerFactory,
        _keepAwake = keepAwake,
        _openBlends = openBlends {
    _controller.addListener(_onChanged);
    _settings.addListener(_onChanged);
  }

  final SettingsNotifier _settings;
  final GasAnalysesDaoLike? _analysesDao;
  final LabelPrintService? _labelPrinting;
  final bool _ownsController;
  final AnalyzerController _controller;
  final List<AnalyzerTransportOption> _options;

  /// Injected for tests, which hold the logger and drive it with a manual
  /// clock. When null the session builds [buildOkLogger] with the real clock
  /// and timer.
  final UsbOkLogger Function()? _okLoggerFactory;

  /// Injected for tests, which record when the session asks to stay awake
  /// (true) and lets go (false). When null it uses the platform wakelock.
  final Future<void> Function(bool awake)? _keepAwake;

  /// An OK press that saves complete closes the open blend it matched
  /// (issue #112). Null closes none.
  final OpenBlendsDaoLike? _openBlends;

  int _selected = 0;

  /// Whether the session that produced the current reading was the demo
  /// source, recorded when the session starts. The controller keeps the last
  /// reading after a disconnect and the Source picker is free again, so the
  /// selected option alone says nothing about where a frozen reading came
  /// from. Null until a first session starts.
  bool? _sessionIsDemo;

  /// The Log on OK logger while it is wanted, and the transport it watches.
  UsbOkLogger? _okLogger;
  AnalyzerTransport? _okTransport;

  /// The Log on OK and 5 V settings last sent to the bridge in this session,
  /// and the transport they were sent to; see [_syncBridge].
  (bool, bool)? _bridgeConfig;
  BleBridgeTransport? _bridgeConfigFor;

  /// Follows the bridge's status so the connection strip redraws on `ST`.
  StreamSubscription<void>? _bridgeSub;
  BleBridgeTransport? _bridgeSubFor;

  /// The bridge's OK records handler and its live-state reporter, while the
  /// session is on [_bridgeOkFor]; see [_syncBridgeOk].
  BleBridgeTransport? _bridgeOkFor;
  BridgeOkHandler? _bridgeOkHandler;
  StreamSubscription<BridgeMessage>? _bridgeOkSub;
  BridgeStateReporter? _stateReporter;

  bool _disposed = false;

  AnalyzerController get controller => _controller;

  /// The log Log on OK and the save card save to; null hides both.
  GasAnalysesDaoLike? get analysesDao => _analysesDao;

  /// Cylinder label printing; null hides the print actions.
  LabelPrintService? get labelPrinting => _labelPrinting;
  List<AnalyzerTransportOption> get options => _options;
  int get selected => _selected;
  bool? get sessionIsDemo => _sessionIsDemo;

  /// Whether the source in use is the demo's; see [analyzerSourceIsDemo].
  bool get sourceIsDemo => analyzerSourceIsDemo(
        inSession: _controller.isBusy,
        sessionIsDemo: _sessionIsDemo,
        selectedIsDemo: _options[_selected].isDemo,
      );

  /// The handler of the bridge's OK records; non-null while the session is
  /// on the bridge and there is a log, also with Log on OK off.
  BridgeOkHandler? get bridgeOkHandler => _bridgeOkHandler;

  /// The Log on OK logger the save card binds; non-null while it runs: the
  /// USB logger, or over the bridge its record handler while the switch is
  /// on.
  OkLogger? get okLogger =>
      _okLogger ?? (_settings.analyzerLogOnOk ? _bridgeOkHandler : null);
  bool get okRunning => okLogger != null;

  /// While the logger is watching and the SOLO has streamed and gone quiet,
  /// OK was pressed and the SOLO holds its reading.
  bool get held =>
      okRunning && _controller.hasHadData && _controller.noDataHint;

  /// Picks the source for the next connect. Ignored while a session is on.
  void select(int index) {
    if (_controller.isBusy) return;
    if (index == _selected) return;
    _selected = index;
    notifyListeners();
  }

  /// Connects the selected source; [BuildContext] is for options with a
  /// picker ([AnalyzerTransportOption.choose]). Does nothing when the diver
  /// cancels the picker.
  Future<void> connectSelected(BuildContext context) async {
    if (_controller.isBusy) return;
    final option = _options[_selected];
    final choose = option.choose;
    final transport = choose != null ? await choose(context) : option.create();
    if (transport == null) return;
    if (_disposed) {
      await transport.dispose();
      return;
    }
    // Before connecting: the controller clears the old reading as it
    // starts, and the new session's readings can arrive during connect.
    // If the connect fails there is no reading, so the flag isn't used.
    _sessionIsDemo = option.isDemo;
    notifyListeners();
    await _controller.connect(transport);
  }

  Future<void> disconnect() => _controller.disconnect();

  void _onChanged() {
    _syncOkLogger();
    _syncBridge();
    _syncBridgeOk();
    notifyListeners();
  }

  /// While the session is on the bridge (connecting or connected, so the
  /// first `HELLO` is heard): its record handler, when there is a log, and
  /// the live state for the bridge screen, sent while connected. A link that
  /// drops and comes back keeps both; the handler starts over on the new
  /// `HELLO`. Cheap, as the controller calls it on every reading.
  void _syncBridgeOk() {
    final transport = _controller.transport;
    final bridge = transport is BleBridgeTransport && _controller.isBusy
        ? transport
        : null;
    if (!identical(_bridgeOkFor, bridge)) {
      _stopBridgeOk();
      if (bridge != null) _startBridgeOk(bridge);
    }
    final reporter = _stateReporter;
    if (reporter == null) return;
    if (_controller.isConnected) {
      reporter
        ..start()
        ..update(_controller.latest, _controller.stability);
    } else {
      reporter.stop();
    }
  }

  void _startBridgeOk(BleBridgeTransport bridge) {
    _bridgeOkFor = bridge;
    _stateReporter = BridgeStateReporter(send: bridge.send);
    final dao = _analysesDao;
    if (dao == null) return;
    final handler = buildBridgeOkHandler(
      dao: dao,
      printing: _labelPrinting,
      send: bridge.send,
      openBlends: _openBlends,
      active: () =>
          identical(_controller.transport, bridge) && _controller.isConnected,
    );
    _bridgeOkHandler = handler;
    // The HELLO can be in before this runs (the transport is connected by
    // it); a second one only starts the handler over again.
    final hello = bridge.lastHello;
    if (hello != null) handler.onMessage(hello);
    _bridgeOkSub = bridge.messages.listen(handler.onMessage);
  }

  /// Stops the handler and the reporter. A record being handled finishes,
  /// is saved and reported; its ACK goes nowhere once the link is closed,
  /// and the bridge sends it again next time.
  void _stopBridgeOk() {
    _bridgeOkFor = null;
    _stateReporter?.stop();
    _stateReporter = null;
    // Not awaited: see [dispose].
    unawaited(_bridgeOkSub?.cancel());
    _bridgeOkSub = null;
    final handler = _bridgeOkHandler;
    _bridgeOkHandler = null;
    if (handler != null) unawaited(handler.dispose());
  }

  /// While the session runs over the bridge: redraw when its status
  /// changes, and tell it when Log on OK or the 5 V switch changed. The
  /// handshake already sent the values of the moment, so the first call
  /// for a connection only notes them.
  void _syncBridge() {
    final transport = _controller.transport;
    final bridge = transport is BleBridgeTransport ? transport : null;

    if (!identical(_bridgeSubFor, bridge)) {
      unawaited(_bridgeSub?.cancel());
      _bridgeSubFor = bridge;
      _bridgeSub = bridge?.bridgeChanges.listen((_) {
        if (!_disposed) notifyListeners();
      });
    }

    if (bridge == null || !_controller.isConnected) {
      _bridgeConfig = null;
      _bridgeConfigFor = null;
      return;
    }
    final config = (_settings.analyzerLogOnOk, _settings.analyzerBridgeVbus);
    if (!identical(_bridgeConfigFor, bridge)) {
      _bridgeConfigFor = bridge;
      _bridgeConfig = config;
    } else if (_bridgeConfig != config) {
      _bridgeConfig = config;
      unawaited(bridge.sendConfig());
    }
  }

  /// Whether the USB Log on OK logger should be running now: the switch is
  /// on, there is a log to save to, and the session that is connected is not
  /// the demo's. Over the bridge it is never wanted: the bridge makes the
  /// records itself, and [_syncBridgeOk] handles them.
  bool get _okWanted =>
      _settings.analyzerLogOnOk &&
      _analysesDao != null &&
      _sessionIsDemo == false &&
      _controller.isConnected &&
      _controller.transport is! BleBridgeTransport;

  /// Builds and attaches the logger when Log on OK is wanted, and disposes
  /// it when it no longer is or the session's transport changed. Cheap, as
  /// the controller calls it on every reading. The card gets the logger in
  /// the build that follows the notification.
  void _syncOkLogger() {
    final transport = _controller.transport;
    if (!_okWanted || transport == null) {
      _stopOkLogger();
      return;
    }
    if (_okLogger != null && !identical(_okTransport, transport)) {
      _stopOkLogger();
    }
    if (_okLogger != null) return;
    final logger = _okLoggerFactory?.call() ??
        buildOkLogger(
          dao: _analysesDao!,
          printing: _labelPrinting,
          openBlends: _openBlends,
        );
    logger.attach(transport);
    _okLogger = logger;
    _okTransport = transport;
    unawaited((_keepAwake ?? _setWakelock)(true));
  }

  /// Detaches and disposes the logger. A press it is handling still
  /// finishes and is saved.
  void _stopOkLogger() {
    final logger = _okLogger;
    if (logger == null) return;
    _okLogger = null;
    _okTransport = null;
    unawaited(logger.dispose());
    unawaited((_keepAwake ?? _setWakelock)(false));
  }

  @override
  void dispose() {
    _disposed = true;
    _controller.removeListener(_onChanged);
    _settings.removeListener(_onChanged);
    unawaited(_bridgeSub?.cancel());
    _bridgeSub = null;
    _stopOkLogger();
    _stopBridgeOk();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }
}

/// The [UsbOkLogger] the analyzer session uses: saves go to [dao] under the
/// id of the press (a press that was already saved is not saved twice), a
/// label is printed through [printing], and an error that is not the diver's
/// goes to Sentry.
///
/// The logger is built once per session, so whether a printer is set up is
/// left to the print itself and to the save card, which says at each press
/// whether it is ([LogOnOkSetup.printerConfigured]). A printer set up after
/// the connect (through the card's link) is used from the next press.
///
/// A [LabelPrinterException] (printer off or not found, cover open, no
/// labels) is the diver's situation, not a bug: the card already says the
/// press needs a sign-off, so it is not reported.
///
/// [elapsed], [tickInterval] and [report] are for tests; the session leaves
/// them out. A null [tickInterval] switches the timer off, so no OK would
/// ever be seen.
@visibleForTesting
UsbOkLogger buildOkLogger({
  required GasAnalysesDaoLike dao,
  LabelPrintService? printing,
  OpenBlendsDaoLike? openBlends,
  Duration Function()? elapsed,
  Duration? tickInterval = kOkTickInterval,
  void Function(Object error, StackTrace stack)? report,
}) =>
    UsbOkLogger(
      save: dao.addFromBridge,
      markComplete: (id) => dao.setNeedsSignoff(id, false),
      printLabel: printing == null
          ? null
          : (a, copies) => printing.printAnalysis(a, copies: copies),
      closeBlend: openBlends?.closeBlend,
      elapsed: elapsed,
      tickInterval: tickInterval,
      onError: (e, s) {
        if (e is LabelPrinterException) return;
        (report ?? (e, s) => Sentry.captureException(e, stackTrace: s))(e, s);
      },
    );

/// The [BridgeOkHandler] the analyzer session uses on the bridge: saves go
/// to [dao] under the record's derived id (a record delivered again is not
/// saved twice), a label is printed through [printing], [send] goes to the
/// bridge, and an error that is not the diver's goes to Sentry, as in
/// [buildOkLogger].
@visibleForTesting
BridgeOkHandler buildBridgeOkHandler({
  required GasAnalysesDaoLike dao,
  LabelPrintService? printing,
  required Future<void> Function(String message) send,
  required bool Function() active,
  OpenBlendsDaoLike? openBlends,
  Duration Function()? elapsed,
  void Function(Object error, StackTrace stack)? report,
}) {
  void onError(Object e, StackTrace s) {
    if (e is LabelPrinterException) return;
    (report ?? (e, s) => Sentry.captureException(e, stackTrace: s))(e, s);
  }

  return BridgeOkHandler(
    processor: OkRecordProcessor(
      save: dao.addFromBridge,
      markComplete: (id) => dao.setNeedsSignoff(id, false),
      printLabel: printing == null
          ? null
          : (a, copies) => printing.printAnalysis(a, copies: copies),
      closeBlend: openBlends?.closeBlend,
      onError: onError,
    ),
    send: send,
    active: active,
    elapsed: elapsed,
    onError: onError,
  );
}

/// Whether the source in use is the demo's. While a session is on it is the
/// session's ([sessionIsDemo], recorded when it started), because that is what
/// Log on OK goes by; otherwise it is the option selected in the picker.
@visibleForTesting
bool analyzerSourceIsDemo({
  required bool inSession,
  required bool? sessionIsDemo,
  required bool selectedIsDemo,
}) =>
    inSession && sessionIsDemo != null ? sessionIsDemo : selectedIsDemo;

/// Switches the platform wakelock on or off. Log on OK holds it while it is
/// watching the SOLO: once the display sleeps, the system idles and App Nap
/// (macOS) throttles the app, the stream of lines stops being seen and an OK
/// press goes unnoticed. Errors are swallowed: unsupported targets no-op, and
/// tests can hit MissingPluginException.
Future<void> _setWakelock(bool enable) async {
  try {
    if (enable) {
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
  } catch (e) {
    debugPrint('Wakelock ${enable ? 'enable' : 'disable'} failed '
        '(non-fatal): $e');
  }
}
