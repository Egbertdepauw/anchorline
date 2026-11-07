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
/// Layout: on phones one scrolling column with the save section's action bar
/// pinned under it; from [kAnalyzerWideBreakpoint] up, the connection strip
/// across the top, readings, planning and trend on the left, and the save
/// section on the right with its action bar at the bottom of that column.
///
/// The Analyse tab of the Gas destination: no app bar of its own.
///
/// "Log on OK" (#113): started from the save section's heading while a real
/// analyzer is connected, the shell-owned [AnalyzerSession] runs a logger
/// that watches the session's lines, and an OK press on the SOLO saves an
/// analysis (and prints its label) from the setup on the save card. While it
/// runs the action bar is a status strip with Stop. The session, not this
/// screen, owns the connection and the logger, so they outlive the screen;
/// the save card's [AnalysisSaveController] only hands the logger the setup
/// to save with.
library;

import 'package:flutter/material.dart';

import '../../analyzer/analyzer_controller.dart';
import '../../data/db/gas_analyses_dao.dart';
import '../../labels/label_print_service.dart';
import '../notifiers/analyzer_session.dart';
import '../notifiers/blend_notifier.dart';
import '../notifiers/settings_notifier.dart';
import '../theme/tokens.dart';
import '../widgets/analysis_action_bar.dart';
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

  /// The same for the action bar: a save started from it keeps the context
  /// of its confirm dialog when the layout changes.
  final _actionBarKey = GlobalKey();

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
      // The save controller notifies while this builds (see
      // [AnalysisSaveController.update]), so everything that listens to it,
      // the action bar included, is built below here.
      builder: (context, _) {
        _syncSaveController();
        return LayoutBuilder(
          builder: (context, constraints) =>
              constraints.maxWidth >= kAnalyzerWideBreakpoint
                  ? _wideLayout()
                  : _narrowLayout(),
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
      ..onBlendTargetUsed = widget.blend?.markRecentTargetUsed
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

  /// One scrolling column, with the action bar pinned under it.
  Widget _narrowLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            key: const ValueKey('analyzer-scroll'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConnectionStrip(session: _session),
                ConnectionNotices(session: _session),
                _band(wide: false),
                _planning(wide: false),
                TrendRow(controller: _controller),
                ..._saveCard(),
              ],
            ),
          ),
        ),
        ..._actionBar(),
      ],
    );
  }

  /// The save section's action bar; empty while the section is not shown.
  List<Widget> _actionBar() {
    final save = _saveController;
    if (save == null) return const [];
    return [
      AnalysisActionBar(
        key: _actionBarKey,
        controller: save,
        okHeld: _session.held,
        onStopLogOnOk: () => widget.settings.setAnalyzerLogOnOk(false),
      ),
    ];
  }

  /// Log on OK (#113) is offered: there is a log to save to and the source
  /// is not the demo, whose readings are made up (the session's source while
  /// one is on, as for the session's Log on OK).
  bool get _offersLogOnOk => _analysesDao != null && !_session.sourceIsDemo;

  /// The "Log on OK" button can start it: a real (non-Demo) analyzer is
  /// connected and there is a log. Started, it is remembered on the device
  /// and runs again on the next connect; the session runs the logger.
  bool get _canStartLogOnOk =>
      _controller.isConnected && !_session.sourceIsDemo && _analysesDao != null;

  /// Whether the save card is shown; see [_saveCard].
  bool get _showsSaveCard {
    if (_analysesDao == null) return false;
    final readingFromDemo =
        _controller.latest == null ? null : _session.sessionIsDemo;
    return !(readingFromDemo ?? _session.options[_session.selected].isDemo);
  }

  /// The "Save analysis" section (#111); empty without a DAO, and for
  /// readings from the demo source (they are made up). It goes
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
      AnalysisSaveCard(
        key: _saveCardKey,
        controller: save,
        offersLogOnOk: _offersLogOnOk,
        onStartLogOnOk: _canStartLogOnOk
            ? () => widget.settings.setAnalyzerLogOnOk(true)
            : null,
        onSetUpPrinter: printing == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => LabelPrinterSettingsScreen(
                    settings: widget.settings,
                    printing: printing,
                  ),
                )),
      ),
    ];
  }

  /// The strip across the top; readings, planning and trend on the left
  /// (about 60 %); the save section on the right with its action bar at the
  /// bottom of the column.
  Widget _wideLayout() {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConnectionStrip(session: _session),
        ConnectionNotices(session: _session),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  key: const ValueKey('analyzer-scroll'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _band(wide: true),
                      _planning(wide: true),
                      TrendRow(controller: _controller),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                        left: BorderSide(color: palette.surfaceRaised)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          key: const ValueKey('analyzer-save-scroll'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ..._saveCard(),
                            ],
                          ),
                        ),
                      ),
                      ..._actionBar(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
