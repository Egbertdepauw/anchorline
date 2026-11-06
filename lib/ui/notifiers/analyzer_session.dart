/// The analyzer connection and Log on OK, owned by the app shell so they
/// outlive the screen that shows them: the SOLO stays connected and an OK
/// press is still saved while the diver is on another tab.
library;

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:sentry_flutter/sentry_flutter.dart' show Sentry;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../analyzer/analyzer_controller.dart';
import '../../analyzer/transport/analyzer_transport.dart';
import '../../analyzer/transport/analyzer_transport_options.dart';
import '../../analyzer/usb_ok_logger.dart';
import '../../data/db/gas_analyses_dao.dart';
import '../../label_printer/label_printer.dart' show LabelPrinterException;
import '../../labels/label_print_service.dart';
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
  })  : _settings = settings,
        _analysesDao = analysesDao,
        _labelPrinting = labelPrinting,
        _ownsController = controller == null,
        _controller = controller ?? AnalyzerController(),
        _options = transportOptions ?? defaultAnalyzerTransportOptions(),
        _okLoggerFactory = okLoggerFactory,
        _keepAwake = keepAwake {
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

  bool _disposed = false;

  AnalyzerController get controller => _controller;
  List<AnalyzerTransportOption> get options => _options;
  int get selected => _selected;
  bool? get sessionIsDemo => _sessionIsDemo;

  /// Whether the source in use is the demo's; see [analyzerSourceIsDemo].
  bool get sourceIsDemo => analyzerSourceIsDemo(
        inSession: _controller.isBusy,
        sessionIsDemo: _sessionIsDemo,
        selectedIsDemo: _options[_selected].isDemo,
      );

  /// The Log on OK logger; non-null while it runs.
  UsbOkLogger? get okLogger => _okLogger;
  bool get okRunning => _okLogger != null;

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
    notifyListeners();
  }

  /// Whether Log on OK should be running now: the switch is on, there is a
  /// log to save to, and the session that is connected is not the demo's.
  bool get _okWanted =>
      _settings.analyzerLogOnOk &&
      _analysesDao != null &&
      _sessionIsDemo == false &&
      _controller.isConnected;

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
        buildOkLogger(dao: _analysesDao!, printing: _labelPrinting);
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
    _stopOkLogger();
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
      elapsed: elapsed,
      tickInterval: tickInterval,
      onError: (e, s) {
        if (e is LabelPrinterException) return;
        (report ?? (e, s) => Sentry.captureException(e, stackTrace: s))(e, s);
      },
    );

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
