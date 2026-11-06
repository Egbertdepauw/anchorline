/// Live gas-analyzer screen (Divesoft SOLO).
///
/// A connection strip, the measured mix with a stability pill and big O2 /
/// He / N2 readouts, a planning grid (MOD per configured ppO2, END, min
/// depth, density, temperature, ambient pressure) and a collapsed
/// two-minute trend. The pieces live in `widgets/analyzer/`. Works with any
/// [AnalyzerTransport]: desktop USB serial, Android USB and the demo simulator.
/// Further transports (the BLE bridge, #113) plug in as extra
/// [AnalyzerTransportOption]s in [defaultAnalyzerTransportOptions].
///
/// Layout: one column on phones; from [kAnalyzerWideBreakpoint] up, readings,
/// planning and trend on the left and the save section on the right.
///
/// The Analyse tab of the Gas destination: no app bar of its own.
///
/// "Log on OK" (#113): with the switch on and a real analyzer connected, the
/// shell-owned [AnalyzerSession] runs a logger that watches the session's
/// lines, and an OK press on the SOLO saves an analysis (and prints its
/// label) from the setup on the save card. The session, not this screen,
/// owns the connection and the logger, so they outlive the screen; the
/// save card's [AnalysisSaveController] only hands the logger the setup to
/// save with.
library;

import 'package:flutter/material.dart';

import '../../analyzer/analyzer_controller.dart';
import '../../data/db/gas_analyses_dao.dart';
import '../../labels/label_print_service.dart';
import '../notifiers/analyzer_session.dart';
import '../notifiers/blend_notifier.dart';
import '../notifiers/settings_notifier.dart';
import '../theme/tokens.dart';
import '../widgets/analysis_save_card.dart';
import '../widgets/analysis_save_controller.dart';
import '../widgets/analyzer/connection_strip.dart';
import '../widgets/analyzer/planning_grid.dart';
import '../widgets/analyzer/readout_band.dart';
import '../widgets/analyzer/trend_row.dart';
import '../widgets/label_printer_settings_section.dart';

export '../../analyzer/transport/analyzer_transport_options.dart';
export '../widgets/analyzer/planning_grid.dart'
    show kAnalyzerCcrDiluentPpo2, kAnalyzerReferencePpo2;
export '../widgets/analyzer/readout_band.dart' show StabilityPill;

/// Width from which the screen switches to the two-column grid.
const double kAnalyzerWideBreakpoint = 840;

class AnalyzerScreen extends StatefulWidget {
  const AnalyzerScreen({
    super.key,
    required this.settings,
    required this.session,
    this.blend,
  });

  final SettingsNotifier settings;

  /// The analyzer connection and Log on OK, owned by the app shell.
  final AnalyzerSession session;

  /// The Blend tab's notifier, read live: its recent target (#114) is
  /// offered first as the desired mix on the save card.
  final BlendNotifier? blend;

  @override
  State<AnalyzerScreen> createState() => _AnalyzerScreenState();
}

class _AnalyzerScreenState extends State<AnalyzerScreen> {
  AnalyzerSession get _session => widget.session;
  AnalyzerController get _controller => _session.controller;
  GasAnalysesDaoLike? get _analysesDao => _session.analysesDao;
  LabelPrintService? get _labelPrinting => _session.labelPrinting;

  /// The save card's form: the setup the diver filled in and its save
  /// logic. Non-null while the card is shown; see [_syncSaveController].
  AnalysisSaveController? _saveController;

  /// Keeps the save card's widgets when the window crosses
  /// [kAnalyzerWideBreakpoint] and the card moves to the other layout. The
  /// setup itself is in [_saveController]; the key keeps what lives in the
  /// widgets, such as the focus of a field being typed in and the context of
  /// a save whose confirm dialog is open.
  final _saveCardKey = GlobalKey();

  @override
  void didUpdateWidget(AnalyzerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The form saves to the session's log with the settings it was made
    // with; another session or settings get a form of their own.
    if (!identical(oldWidget.session, widget.session) ||
        !identical(oldWidget.settings, widget.settings)) {
      _retireSaveController();
    }
  }

  @override
  void dispose() {
    _saveController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [_session, widget.settings, if (widget.blend != null) widget.blend!]),
      builder: (context, _) {
        _syncSaveController();
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= kAnalyzerWideBreakpoint;
            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: Spacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConnectionStrip(session: _session),
                  ConnectionNotices(session: _session),
                  wide ? _wideLayout() : _narrowLayout(),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Keeps [_saveController] in step with the screen, on every build: made
  /// when the save card is shown, retired when it goes away (so a card shown
  /// again starts fresh, from the remembered name), and told the reading,
  /// the Blend target, the connection and the Log on OK logger.
  void _syncSaveController() {
    final dao = _analysesDao;
    if (dao == null || !_showsSaveCard) {
      _retireSaveController();
      return;
    }
    final save = _saveController ??= AnalysisSaveController(
      dao: dao,
      settings: widget.settings,
      labelPrinting: _labelPrinting,
    );
    save
      ..update(
        reading: _controller.latest,
        stability: _controller.stability,
        blendTarget: widget.blend?.recentTarget(),
        unusedBlendTarget: widget.blend?.unusedRecentTarget(),
        connected: _controller.isConnected,
      )
      ..bindLogger(_session.okLogger);
  }

  /// Lets go of [_saveController]; the next build makes a new one if the
  /// card is shown. It is disposed after the frame, as the card that shows
  /// it stays in the tree until then.
  void _retireSaveController() {
    final old = _saveController;
    if (old == null) return;
    _saveController = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  Widget _band({required bool wide}) => ReadoutBand(
        reading: _controller.latest,
        stability: _controller.stability,
        wide: wide,
      );

  /// The MOD rows are judged against the desired mix picked on the save
  /// card, while the card is shown, so they follow the label's depth rule
  /// (issue #145).
  Widget _planning({required bool wide}) {
    final save = _saveController;
    return ListenableBuilder(
      listenable: Listenable.merge([?save]),
      builder: (_, _) => PlanningGrid(
        reading: _controller.latest,
        settings: widget.settings,
        desired: save?.desiredMix,
        wide: wide,
      ),
    );
  }

  Widget _narrowLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _band(wide: false),
        _planning(wide: false),
        TrendRow(controller: _controller),
        ..._logOnOkSwitch(),
        ..._saveCard(),
      ],
    );
  }

  /// The "Log on OK" switch (#113), followed by a gap; empty without a log
  /// to save to and for the demo source, whose readings are made up (the
  /// session's source while one is on, as for the session's Log on OK). The switch is
  /// remembered on the device; the logger itself runs only while a real
  /// session is connected.
  List<Widget> _logOnOkSwitch() {
    if (_analysesDao == null || _session.sourceIsDemo) return const [];
    // While the logger is watching and the SOLO has streamed and gone quiet,
    // OK was pressed: say so in the switch's own subtitle, so nothing moves.
    final held = _session.held;
    return [
      SwitchListTile(
        key: const ValueKey('analyzer-log-on-ok'),
        contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        title: const Text('Log on OK'),
        subtitle: Text(
          held
              ? 'Held on the SOLO. Press OK there to measure again.'
              : 'Press OK on the SOLO to save. Keep this screen open.',
          key: const ValueKey('analyzer-log-on-ok-subtitle'),
        ),
        value: widget.settings.analyzerLogOnOk,
        onChanged: widget.settings.setAnalyzerLogOnOk,
      ),
      const SizedBox(height: Spacing.sm),
    ];
  }

  /// Whether the save card is shown; see [_saveCard].
  bool get _showsSaveCard {
    if (_analysesDao == null) return false;
    final readingFromDemo =
        _controller.latest == null ? null : _session.sessionIsDemo;
    return !(readingFromDemo ?? _session.options[_session.selected].isDemo);
  }

  /// The "Save analysis" card (#111), preceded by a gap; empty without a
  /// DAO, and for readings from the demo source (they are made up). It goes
  /// by the session the reading came from ([AnalyzerSession.sessionIsDemo]), not the
  /// selected option, because a reading outlives its session and the diver
  /// can switch source in between. With no reading there is no session to
  /// ask (nothing yet, or a connect that failed), so the selected option
  /// decides.
  List<Widget> _saveCard() {
    final save = _saveController;
    if (save == null) return const [];
    final printing = _labelPrinting;
    return [
      const SizedBox(height: Spacing.md),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        child: AnalysisSaveCard(
        key: _saveCardKey,
        controller: save,
        onSetUpPrinter: printing == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => LabelPrinterSettingsScreen(
                    settings: widget.settings,
                    printing: printing,
                  ),
                )),
        ),
      ),
    ];
  }

  Widget _wideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _band(wide: true),
              _planning(wide: true),
              TrendRow(controller: _controller),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: Spacing.sm),
              ..._logOnOkSwitch(),
              ..._saveCard(),
            ],
          ),
        ),
      ],
    );
  }
}
