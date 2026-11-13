/// The state and logic of the "Save analysis" form on the gas-analyzer
/// screen (issues #111, #113, #114), apart from the widgets that show it, so
/// the form and its actions can be separate widgets that share one state.
///
/// The analyzer screen owns the controller while it shows the form, and
/// tells it the live reading, the connection and the Log on OK logger on
/// every build ([update], [bindLogger]). The form's widgets
/// listen to it and call its actions.
///
/// It captures the current reading plus the diver's context (cylinder from
/// Equipment, who analysed, fill pressure, notes) into the synced cylinder
/// analysis log. A reading that isn't STABLE asks for confirmation first;
/// it's never blocked, because a diver at the fill station sometimes has to
/// log what they've got.
///
/// For cylinder labels the form also holds the desired mix and the gas role.
/// The desired mix is picked automatically (spec §4.3): the open blend that
/// matches the reading or the nearest standard mix, and only when it grades
/// match or orange against the reading, because up to a red match the label
/// prints its name. A chip the diver taps is their pick until the next
/// manual save.
///
/// A save closes an open blend (issue #112, [blendToClose]): the one the
/// reading matches, the oldest of the mix the diver tapped, or the one the
/// diver chose with [chooseBlend]. The analysis then takes the blend's target
/// as its desired mix and the blend's role. A residual analysis ([residual])
/// closes nothing, has no desired mix and isn't printed; it fills the Blend
/// tab's residual gas through [onResidualSaved].
///
/// The role follows the rule of [resolveGasRole]: a tapped role, else the
/// blend's, else the picked cylinder's, else Bailout above 30 % O2. "Save & print"
/// saves the analysis and then prints its label. A hard mismatch with the
/// desired mix is confirmed before anything is saved; a print that fails
/// leaves the analysis saved.
///
/// With an [OkLogger] bound (Log on OK, over USB or the bridge) the form is
/// the setup for the OK presses: its fields are what the next OK press saves
/// ([okSetup]), and the outcome of each press is kept in [okResult] for Edit.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../analysis/fill_pressure.dart';
import '../../analysis/gas_naming.dart';
import '../../analysis/mix_match.dart';
import '../../analysis/open_blend_match.dart';
// The getter [AnalysisSaveController.nearestUnmatched] shadows the function.
import '../../analysis/open_blend_match.dart' as match;
import '../../analysis/standard_mix_pick.dart';
import '../../analyzer/blend_closer.dart';
import '../../analyzer/bridge/bridge_protocol.dart';
import '../../analyzer/bridge/record_to_analysis.dart';
import '../../analyzer/protocol/analyzer_reading.dart';
import '../../analyzer/stability.dart';
import '../../analyzer/ok_logger.dart';
import '../../data/db/gas_analyses_dao.dart';
import '../../data/db/open_blends_dao.dart';
import '../../labels/label_print_service.dart';
import '../notifiers/settings_notifier.dart';
import 'analysis_action_bar.dart' show kSnackBarClearOfActionBar;
import 'analysis_edit_sheet.dart';
import 'label_print_controls.dart';
import 'mix_mismatch_dialog.dart';

class AnalysisSaveController extends ChangeNotifier {
  /// "Analysed by" starts from "Your initials" in [settings] (and again on
  /// every connect), the fill pressure from "Fill pressure starts at", and
  /// "Print a label on each OK" from the choice remembered there.
  AnalysisSaveController({
    required GasAnalysesDaoLike dao,
    required SettingsNotifier settings,
    LabelPrintService? labelPrinting,
    OpenBlendsDaoLike? openBlends,
    this.onResidualSaved,
    DateTime Function() now = DateTime.now,
  })  : _dao = dao,
        _settings = settings,
        _labelPrinting = labelPrinting,
        _openBlends = openBlends,
        _now = now,
        _printOnOk = settings.analyzerPrintOnOk,
        analysedBy = TextEditingController(text: settings.yourInitials ?? '') {
    fillPressure.text = _startPressure();
    _seenFillPressure = fillPressure.text;
    fillPressure.addListener(_onFillPressure);
    unawaited(_loadCylinders());
    unawaited(_loadMixOptions());
    _watchOpenBlends();
  }

  final GasAnalysesDaoLike _dao;
  final SettingsNotifier _settings;
  final LabelPrintService? _labelPrinting;
  final OpenBlendsDaoLike? _openBlends;

  /// Called after a residual analysis is saved, with its O2, He and fill
  /// pressure (null when none was entered). The screen sets it to
  /// `BlendNotifier.applyResidualAnalysis`.
  final void Function(double o2, double he, double? bar)? onResidualSaved;

  /// Clock, injectable for tests.
  final DateTime Function() _now;

  /// The form's text fields.
  final TextEditingController analysedBy;
  final TextEditingController analysedFor = TextEditingController();
  final TextEditingController fillPressure = TextEditingController();
  final TextEditingController notes = TextEditingController();

  /// The form's desired-mix row, brought into view by "Change desired mix"
  /// in the hard-mismatch dialog. The form puts it on that row.
  final GlobalKey mixRowKey = GlobalKey();

  bool _disposed = false;

  // ── What the screen tells it ────────────────────────────────────
  AnalyzerReading? _reading;
  ReadingStability _stability = ReadingStability.noData;
  bool _connected = false;

  /// The live reading to save; null before the first one.
  AnalyzerReading? get reading => _reading;
  ReadingStability get stability => _stability;

  /// The analyzer is connected.
  bool get connected => _connected;

  /// Takes the screen's live values and re-evaluates the automatic mix pick
  /// for the reading. A session that connects (after not being connected)
  /// starts "Analysed by" from "Your initials" again.
  ///
  /// The screen calls this while it builds, and it notifies listeners when
  /// something changed. That is only allowed for listeners inside the
  /// subtree being built, so every widget that listens to this controller
  /// (the save section, the action bar, the planning grid) must sit below
  /// the widget that calls it.
  void update({
    AnalyzerReading? reading,
    required ReadingStability stability,
    required bool connected,
  }) {
    final changed = reading != _reading ||
        stability != _stability ||
        connected != _connected;
    final connecting = connected && !_connected;
    _reading = reading;
    _stability = stability;
    _connected = connected;
    _autoPick = _pickFor(usableGas);
    // Someone else analysing holds until Disconnect; a new session starts
    // from the diver's own initials. Never written back to the settings.
    if (connecting) analysedBy.text = _settings.yourInitials ?? '';
    if (changed) notifyListeners();
  }

  // ── Form state ──────────────────────────────────────────────────
  List<CylinderChoice> _cylinders = const [];
  String? _cylinderId;

  /// The distinct desired mixes of the log's recent analyses, newest first.
  List<DesiredMix> _recentMixes = const [];

  /// The pick follows the reading until the diver taps a chip (or clears
  /// one); a manual save makes it automatic again.
  bool _mixAutomatic = true;

  /// The diver's pick while [_mixAutomatic] is off; null is "no mix".
  DesiredMix? _diverMix;

  /// The automatic pick for the current reading, or null.
  MixPick? _autoPick;

  /// The role the diver tapped, or null to follow the rule.
  GasRole? _tappedRole;

  // ── Open blends ─────────────────────────────────────────────────
  StreamSubscription<List<OpenBlend>>? _openSub;
  List<OpenBlend> _open = const [];

  /// The diver's choice of the blend a save closes; a manual save resets it.
  BlendChoice _choice = const AutoBlend();

  /// "Residual analysis" is on: the next save is a residual.
  bool _residual = false;

  /// "+ Add a note" was tapped; see [notesShown].
  bool _notesOpen = false;
  int _copies = 1;

  /// The fill pressure text the listeners were last told about.
  String _seenFillPressure = '';

  /// A save, with its confirm dialogs, is under way.
  bool _saving = false;

  /// The saved analysis is printing.
  bool _printing = false;

  List<CylinderChoice> get cylinders => _cylinders;

  /// The picked cylinder, while it is still in [cylinders]: one deleted
  /// elsewhere (sync) drops out of the list, and the form should not point
  /// at a value it no longer has.
  String? get cylinderId => _knownCylinderId;
  String? get _knownCylinderId =>
      _cylinders.any((c) => c.id == _cylinderId) ? _cylinderId : null;

  /// The mix chips to offer, at most three so they fit one line on a
  /// phone: the selected mix, then the targets of the open blends, then the
  /// log's recent desired mixes, with no duplicates.
  List<DesiredMix> get mixOptions {
    final out = <DesiredMix>[];
    void add(DesiredMix? m) {
      if (m != null && out.length < _kMaxMixChips && !out.contains(m)) {
        out.add(m);
      }
    }

    add(desiredMix);
    for (final b in _open) {
      add(b.target);
    }
    _recentMixes.forEach(add);
    return out;
  }

  static const _kMaxMixChips = 3;

  /// The desired mix: the target of the blend a save closes, else the
  /// automatic pick for the reading, or the diver's. None for a residual.
  DesiredMix? get desiredMix {
    if (_residual) return null;
    final blend = blendToClose;
    if (blend != null) return blend.target;
    return _mixAutomatic ? _autoPick?.mix : _diverMix;
  }

  /// The desired mix follows the reading (no chip tapped since the last
  /// manual save).
  bool get mixIsAutomatic => _mixAutomatic;

  /// Where the automatic pick came from; null for the diver's pick and when
  /// nothing is picked.
  MixPickSource? get mixSource {
    if (!_mixAutomatic || _residual) return null;
    return blendToClose != null
        ? MixPickSource.blendTarget
        : _autoPick?.source;
  }

  /// The gas role by the rule of [resolveGasRole], for [desiredMix].
  GasRole get role =>
      _roleFor(desiredMix, usableGas?.o2, blendRole: blendToClose?.role);

  /// The diver tapped the role, so [role] is theirs rather than the rule's.
  bool get roleTapped => _tappedRole != null;

  /// The role for [mix] on a reading with [readingO2] % O2: the tapped role,
  /// else the blend's, else the picked cylinder's, else by the O2 of the
  /// mix, or of the reading when there is no mix (none at all is Diluent).
  GasRole _roleFor(
    DesiredMix? mix,
    double? readingO2, {
    GasRole? blendRole,
  }) =>
      resolveGasRole(
        tapped: _tappedRole,
        blendRole: blendRole,
        cylinderRole: _cylinder(_knownCylinderId)?.role,
        o2PercentForRule: mix?.o2Percent.toDouble() ?? readingO2 ?? 0,
      );

  /// The clock the controller uses, for "blended 5 min ago".
  DateTime now() => _now();

  /// The open blends, oldest first.
  List<OpenBlend> get openBlends => _open;

  /// "Residual analysis" is on.
  bool get residual => _residual;

  /// The choice the diver made, with a picked blend that is not open any
  /// more (closed or dismissed elsewhere) counted as automatic.
  BlendChoice get _liveChoice {
    final c = _choice;
    if (c is PickedBlend && !_open.any((b) => b.id == c.blend.id)) {
      return const AutoBlend();
    }
    return c;
  }

  /// The blend a save would close now, or null: [blendForAnalysis] for the
  /// reading, the diver's choice and the mix they tapped. A diver who
  /// cleared the mix on purpose gets no automatic match.
  OpenBlend? get blendToClose {
    final gas = usableGas;
    return gas == null ? null : _blendFor(gas);
  }

  OpenBlend? _blendFor(({double o2, double he}) gas) {
    final choice = _liveChoice;
    if (!_mixAutomatic && _diverMix == null && choice is AutoBlend) {
      return null;
    }
    return blendForAnalysis(
      o2Percent: gas.o2,
      hePercent: gas.he,
      choice: choice,
      chosenMix: _mixAutomatic ? null : _diverMix,
      residual: _residual,
      open: _open,
    );
  }

  /// The nearest open blend when none matches and it grades red or hard,
  /// for the note "No open blend matches. Nearest: ...". Not when the diver
  /// chose a blend, none, or a mix themselves.
  RankedBlend? get nearestUnmatched {
    final gas = usableGas;
    return gas == null ? null : _nearestFor(gas);
  }

  RankedBlend? _nearestFor(({double o2, double he}) gas) {
    if (_residual || !_mixAutomatic || _liveChoice is! AutoBlend) return null;
    if (_blendFor(gas) != null) return null;
    return match.nearestUnmatched(
        o2Percent: gas.o2, hePercent: gas.he, open: _open);
  }

  /// Every open blend graded against the reading, best first, for the
  /// "Change" sheet.
  List<RankedBlend> get blendChoices {
    final gas = usableGas;
    return gas == null
        ? const []
        : rankOpenBlends(o2Percent: gas.o2, hePercent: gas.he, open: _open);
  }

  /// The mismatch warning of the analysis a save would make, against the
  /// blend's target or the desired mix; null for a match, a residual or
  /// nothing to compare.
  MixWarning? get warning {
    final gas = usableGas;
    final target = blendToClose?.target ?? desiredMix;
    if (gas == null || _residual || target == null) return null;
    return mixWarning(
      role: role,
      o2Percent: gas.o2,
      hePercent: gas.he,
      target: target,
      use14ForDeeperMixes: _settings.labelUse14ForDeeperMixes,
    );
  }

  /// The diver picks the blend a save closes, or none, or automatic again.
  void chooseBlend(BlendChoice c) {
    _choice = c;
    _autoPick = _pickFor(usableGas);
    notifyListeners();
  }

  /// "Residual analysis" on or off. A saved residual turns it off again.
  void setResidual(bool on) {
    if (_residual == on) return;
    _residual = on;
    notifyListeners();
  }

  void _watchOpenBlends() {
    final dao = _openBlends;
    if (dao == null) return;
    // Subscribed once, as the Blend tab's list is: a stream made in a build
    // would be a new query on every frame.
    _openSub = dao.watchOpen().listen(
      (list) {
        if (_disposed) return;
        _open = list;
        _autoPick = _pickFor(usableGas);
        notifyListeners();
      },
      onError: (Object e) =>
          debugPrint('Analysis save card: watching the open blends failed: $e'),
    );
  }

  int get copies => _copies;

  /// The Notes field is open: "+ Add a note" was tapped, or it holds text.
  bool get notesShown => _notesOpen || notes.text.isNotEmpty;

  /// A label printer is set up.
  bool get printReady => _labelPrinting?.isConfigured == true;

  /// Prints the label of a saved analysis. With a printer set up the form
  /// offers "Save & print"; without one, the "Set up label printer" link.
  /// Null offers neither.
  LabelPrintService? get labelPrinting => _labelPrinting;

  /// A save or its print is under way.
  bool get busy => _saving || _printing;

  /// O2/He usable for a log entry, or null (no data / sensor error).
  ({double o2, double he})? get usableGas {
    final o2 = _reading?.o2;
    final he = _reading?.he ?? 0;
    if (o2 == null || !o2.isFinite || o2 <= 0 || !he.isFinite) return null;
    return (o2: o2, he: he < 0 ? 0.0 : he);
  }

  /// The fill pressure is blank or a number of bar.
  bool get fillPressureValid => parseFillPressure(fillPressure.text).valid;

  /// "Save analysis" can be tapped now.
  bool get canSave => usableGas != null && !busy && fillPressureValid;

  /// "Save & print" can be tapped now: a residual has no label.
  bool get canSaveAndPrint => canSave && !_residual;

  /// The diver picks a mix with a chip or "Other…", or none (null, the
  /// selected chip tapped again). It is their pick until the next manual
  /// save. A mix of their own replaces a blend they chose: the save closes
  /// the oldest open blend of that mix.
  void pickMix(DesiredMix? mix) {
    _mixAutomatic = false;
    _diverMix = mix;
    _choice = const AutoBlend();
    notifyListeners();
  }

  /// The diver's "no mix": no desired mix until the next manual save.
  void clearMix() => pickMix(null);

  /// The diver taps a gas role, also the one already shown; it wins over the
  /// cylinder and the mix until the next manual save, and for every OK
  /// press until changed.
  void tapRole(GasRole role) {
    _tappedRole = role;
    notifyListeners();
  }

  /// The diver picks a cylinder; its Equipment role then decides the role,
  /// unless the diver tapped one.
  void selectCylinder(String? id) {
    _cylinderId = id;
    notifyListeners();
  }

  /// "+ Add a note": shows the Notes field.
  void openNotes() {
    _notesOpen = true;
    notifyListeners();
  }

  void setCopies(int copies) {
    _copies = copies;
    notifyListeners();
  }

  CylinderChoice? _cylinder(String? id) =>
      _cylinders.where((c) => c.id == id).firstOrNull;

  /// The automatic pick for [gas]: the target of the open blend that
  /// matches it, or the nearest standard mix, within orange, or null.
  MixPick? _pickFor(({double o2, double he})? gas) => gas == null
      ? null
      : pickDesiredMix(
          o2Percent: gas.o2,
          hePercent: gas.he,
          // With "None" chosen the pick is a standard mix, so the verdict
          // and the row agree that no open blend is involved.
          blendTarget:
              _choice is NoBlend ? null : _autoBlendFor(gas)?.target,
        );

  /// The blend the app matches to [gas] by itself.
  OpenBlend? _autoBlendFor(({double o2, double he}) gas) => blendForAnalysis(
        o2Percent: gas.o2,
        hePercent: gas.he,
        choice: const AutoBlend(),
        residual: false,
        open: _open,
      );

  /// "Fill pressure starts at", written whole when it is whole (`230`).
  String _startPressure() {
    final bar = _settings.analyzerFillPressureStartBar;
    return bar == bar.truncateToDouble() ? '${bar.toInt()}' : '$bar';
  }

  /// The fill pressure decides [fillPressureValid] and [canSave].
  void _onFillPressure() {
    if (fillPressure.text == _seenFillPressure) return;
    _seenFillPressure = fillPressure.text;
    notifyListeners();
  }

  Future<void> _loadCylinders() async {
    final list = await _dao.listCylinderChoices();
    if (_disposed) return;
    _cylinders = list;
    notifyListeners();
  }

  /// Loads the log's recent desired mixes for [mixOptions]. Reloaded after
  /// each save, so the mix just used (perhaps typed in through "Other…") is
  /// one tap away for the next cylinder. A failed read keeps the options
  /// there are.
  Future<void> _loadMixOptions() async {
    final List<GasAnalysis> log;
    try {
      log = await _dao.list();
    } catch (e) {
      debugPrint('Analysis save card: loading the recent mixes failed: $e');
      return;
    }
    if (_disposed) return;
    _recentMixes = recentDesiredMixes(log);
    notifyListeners();
  }

  static String? _blankToNull(String s) => s.trim().isEmpty ? null : s;

  // ── Manual save ─────────────────────────────────────────────────

  /// "Save", and with [print] "Save & print". Confirms an unstable reading
  /// and, before printing, a hard mismatch with the desired mix; then saves;
  /// then prints what was saved. A failed save prints nothing. A failed
  /// print leaves the analysis saved, and its Retry only prints. [context]
  /// shows the dialogs and the SnackBars; the save stops when it is gone.
  ///
  /// Everything saved is taken when the save starts, before any dialog: the
  /// reading, and the desired mix and role worked out for that reading. An
  /// automatic pick is never taken from a later line. So is the blend it
  /// closes: one chosen but closed elsewhere meanwhile falls back to the
  /// oldest open blend of its mix, or closes nothing, and the analysis is
  /// saved all the same.
  Future<void> save(BuildContext context, {bool print = false}) async {
    final printTo = print && !_residual ? _labelPrinting : null;
    final gas = usableGas;
    final pressure = parseFillPressure(fillPressure.text);
    // The guard goes up before the first await, so a second tap while a
    // dialog opens or the save runs can't save the reading twice.
    if (gas == null || busy || !pressure.valid) return;
    _saving = true;
    notifyListeners();
    try {
      // Snapshot before any await: the reading keeps updating at 1 Hz.
      final reading = _reading!;
      final residual = _residual;
      final blend = _blendFor(gas);
      final nearest = blend == null ? _nearestFor(gas) : null;
      final desired = residual
          ? null
          : blend?.target ?? (_mixAutomatic ? _pickFor(gas)?.mix : _diverMix);
      final analysis = NewGasAnalysis(
        cylinderId: _cylinderId,
        analysedBy: analysedBy.text,
        analysedFor: _blankToNull(analysedFor.text),
        analysedAt: _now(),
        o2Percent: gas.o2,
        hePercent: gas.he,
        fillPressureBar: pressure.bar,
        tempC: reading.tempC != null && reading.tempC!.isFinite
            ? reading.tempC
            : null,
        baroHpa: reading.baroHpa != null && reading.baroHpa!.isFinite
            ? reading.baroHpa
            : null,
        modPpo2s: _settings.analyzerModPpo2s,
        stable: _stability == ReadingStability.stable,
        notes: notes.text,
        desiredMix: desired,
        gasRole: _roleFor(desired, gas.o2, blendRole: blend?.role),
        isResidual: residual,
      );
      final copies = _copies;
      final messenger = ScaffoldMessenger.of(context);
      if (!analysis.stable && !await _confirmUnstable(context)) return;
      if (_disposed || !context.mounted) return;
      if (printTo != null && !await _confirmMix(context, analysis)) return;
      if (_disposed || !context.mounted) return;
      final saved = await _add(
        analysis,
        messenger,
        blend: blend,
        nearest: nearest,
        residualBar: residual ? pressure.bar : null,
      );
      if (saved == null || printTo == null) return;
      if (_disposed || !context.mounted) return;
      _saving = false;
      _printing = true;
      notifyListeners();
      // Retry reads the analysis back first: it may have been edited or
      // deleted in the log by then, and this form may be gone.
      final dao = _dao;
      // Replaces the "Saved …" SnackBar with how the print went.
      await printWithFeedback(
        context,
        service: printTo,
        analysis: saved,
        copies: copies,
        reload: () async =>
            (await dao.list()).where((x) => x.id == saved.id).firstOrNull,
        snackBarMargin: kSnackBarClearOfActionBar,
      );
    } finally {
      if (!_disposed) {
        _saving = false;
        _printing = false;
        notifyListeners();
      }
    }
  }

  Future<bool> _confirmUnstable(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reading not stable'),
        content: const Text(
            'The analyzer hasn\'t settled yet, so this reading may be off. '
            'Wait for STABLE for an accurate value, or save it anyway '
            '(it will be marked as not stable).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('analysis-save-anyway'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save anyway'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Before printing: on a hard mismatch with the desired mix the label
  /// shows the analysed mix, so the diver confirms first. True to go on.
  /// "Change desired mix" stops and brings the mix chips into view.
  Future<bool> _confirmMix(
    BuildContext context,
    NewGasAnalysis analysis,
  ) async {
    final pending = GasAnalysis.fromNew('pending', analysis);
    if (pending.match?.level != MixMatchLevel.hard) return true;
    final choice = await showMixMismatchDialog(context, analysis: pending);
    if (choice == MismatchChoice.changeMix) {
      final mixRow = mixRowKey.currentContext;
      if (mixRow != null && mixRow.mounted) {
        // Only the column the card scrolls in. [Scrollable.ensureVisible]
        // scrolls every scrollable around it, the Gas tabs' page view too:
        // on the wide layout, where the card is the right-hand column,
        // that turned the page over to the Log tab.
        final row = mixRow.findRenderObject();
        final column = Scrollable.maybeOf(mixRow, axis: Axis.vertical);
        if (row != null && column != null) {
          await column.position.ensureVisible(
            row,
            duration: const Duration(milliseconds: 300),
          );
        }
      }
    }
    return choice == MismatchChoice.printAnalysed;
  }

  /// Saves [a] to the log and says so. Returns it as saved, or null when
  /// the save failed (a SnackBar says why, and the diver's choices stay).
  ///
  /// Each result replaces the SnackBar that is up. A print failure from
  /// the previous analysis stays until dismissed (it has a Retry), so a new
  /// bar would queue behind it: a failed save would go unseen, and the old
  /// Retry would still be offered.
  ///
  /// With a [blend] the saved analysis then closes it; a failure there is
  /// logged and leaves the analysis saved. [nearest] is the open blend that
  /// is near but doesn't match, named in the SnackBar. A residual's fill
  /// pressure is [residualBar].
  Future<GasAnalysis?> _add(
    NewGasAnalysis a,
    ScaffoldMessengerState messenger, {
    OpenBlend? blend,
    RankedBlend? nearest,
    double? residualBar,
  }) async {
    final String id;
    try {
      id = await _dao.add(a);
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(_clearOfBar(Text('Save failed: $e')));
      return null;
    }
    final saved = GasAnalysis.fromNew(id, a,
        cylinderLabel: _cylinder(a.cylinderId)?.label);
    if (a.isResidual) {
      // Back to a fill: the next cylinder is not a residual by default.
      _residual = false;
      onResidualSaved?.call(a.o2Percent, a.hePercent, residualBar);
    }
    var closed = false;
    final openBlends = _openBlends;
    if (blend != null && openBlends != null) {
      try {
        closed = await openBlends.closeBlend(blend, id);
      } catch (e) {
        debugPrint('Analysis save card: closing the blend failed: $e');
      }
    }
    if (_disposed) return saved;
    // Keep cylinder, diver and "for" for the next fill. The fill pressure
    // goes back to its start and the note clears. The desired mix goes
    // back to automatic, the role to its rule and the copies to 1: up to a
    // red match the label prints the desired name, so a mix left picked
    // would label the next cylinder with it. A print still uses [saved]
    // and the copies taken with it, the snapshot. In Log on OK mode they
    // are the setup of the next OK press and stay, as a press that saves
    // them leaves them.
    if (_okLogger == null) {
      _mixAutomatic = true;
      _diverMix = null;
      _tappedRole = null;
      _copies = 1;
      _choice = const AutoBlend();
    }
    _notesOpen = false;
    notifyListeners();
    // Not awaited: the print needn't wait for the chips.
    unawaited(_loadMixOptions());
    fillPressure.text = _startPressure();
    notes.clear();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(_clearOfBar(
      Text('Saved ${gasMixName(a.o2Percent, a.hePercent)} to the '
          'analysis log${a.stable ? '' : ' (not stable)'}'
          '${closed ? ' · closes ${blend!.target.name}' : ''}'
          '${!closed && nearest != null ? ' · No open blend matches. '
              'Nearest: ${nearest.blend.target.name} '
              '(${nearest.grade.level.name})' : ''}.'),
    ));
    return saved;
  }

  /// A SnackBar about a save made from the action bar, floating clear of it.
  static SnackBar _clearOfBar(Widget content) => SnackBar(
        content: content,
        behavior: SnackBarBehavior.floating,
        margin: kSnackBarClearOfActionBar,
      );

  // ── Log on OK ───────────────────────────────────────────────────
  OkLogger? _okLogger;
  StreamSubscription<OkLogResult>? _okSub;

  /// The latest OK press of this logger, shown with Edit.
  OkLogResult? _okResult;

  /// Edit of the result is under way.
  bool _okBusy = false;

  /// "Print a label on each OK"; it counts only while a printer is set up.
  bool _printOnOk;

  /// The per-cylinder fields the press of [_okResult] took (from the setup
  /// it carries), for it to use up: by itself when it saved complete, or from
  /// a sign-off on the result row. Only the fields still as they were are
  /// put back to their start, because the diver may already be typing for
  /// the next cylinder while the label prints. Null once used up.
  ({String? cylinderId, double? pressure, String notes})? _takenForResult;

  /// A Log on OK logger is bound: the form is the setup of its OK presses.
  bool get okMode => _okLogger != null;
  OkLogResult? get okResult => _okResult;

  /// Edit of [okResult] is under way.
  bool get okBusy => _okBusy;

  /// "Print a label on each OK", as the diver set it; it counts only while
  /// a printer is set up.
  bool get printOnOk => _printOnOk;

  /// The diver flips "Print a label on each OK"; it is remembered in the
  /// settings.
  void setPrintOnOk(bool on) {
    _printOnOk = on;
    notifyListeners();
    unawaited(_settings.setAnalyzerPrintOnOk(on));
  }

  /// Becomes the setup of [logger] and listens to what its presses did. A
  /// new logger starts a new run, and null ends it. The results are not
  /// replayed, so the controller listens for as long as it has the logger.
  void bindLogger(OkLogger? logger) {
    if (identical(logger, _okLogger)) return;
    _unbindLogger();
    _okResult = null;
    _takenForResult = null;
    if (logger != null) {
      _okLogger = logger;
      logger.setupProvider = okSetup;
      _okSub = logger.results.listen(_onOkResult);
    }
    notifyListeners();
  }

  void _unbindLogger() {
    final logger = _okLogger;
    _okLogger = null;
    // Not awaited: cancelling a broadcast subscription returns a root-zone
    // future, which never completes under the fake clock of widget tests.
    unawaited(_okSub?.cancel());
    _okSub = null;
    // Only this controller's own: one that took the logger over has set
    // its own by now.
    if (logger != null && logger.setupProvider == okSetup) {
      logger.setupProvider = null;
    }
  }

  /// The fields as they are now, for the OK press the logger is handling.
  /// A fill pressure that is not a number is not passed: the field says so,
  /// and the entry is saved without a pressure rather than with a wrong one.
  ///
  /// An automatic mix pick is not passed as a mix: the press picks its own
  /// from its held reading ([LogOnOkSetup.autoPickMix]), and works out its
  /// role from that unless the diver tapped one or the cylinder has one.
  ///
  /// The press matches the open blends itself ([LogOnOkSetup.openBlends],
  /// the diver's [BlendChoice] and "Residual analysis"), with the same rule
  /// as the card, and closes the one it matched when it saves complete.
  /// A picked blend that is not open any more counts as automatic.
  ///
  /// It is the logger's [OkLogger.setupProvider], asked once per press. It
  /// writes nothing to the settings; "Analysed by" is never written back.
  OkSetup okSetup() {
    final printReady = this.printReady;
    final pressure = parseFillPressure(fillPressure.text);
    final cylinderRole = _cylinder(_knownCylinderId)?.role;
    final setup = LogOnOkSetup(
      analysedBy: analysedBy.text,
      desiredMix: _mixAutomatic ? null : _diverMix,
      autoPickMix: _mixAutomatic,
      openBlends: _open,
      blendChoice: _liveChoice,
      residual: _residual,
      tappedRole: _tappedRole,
      cylinderRole:
          cylinderRole == null ? null : gasRoleForCylinderRole(cylinderRole),
      analysedFor: _blankToNull(analysedFor.text),
      printOnOk: printReady && _printOnOk,
      printerConfigured: printReady,
      cylinderId: _knownCylinderId,
      fillPressureBar: pressure.bar,
      notes: notes.text,
      modPpo2s: _settings.analyzerModPpo2s,
    );
    return (setup: setup, copies: _copies);
  }

  /// Keeps the outcome of an OK press. One that saved complete uses up the
  /// per-cylinder fields; a press that needs sign-off leaves them, so OK on
  /// the same cylinder again still has them. The name, desired mix, tapped
  /// role, "for", copies and print switch stay for the next cylinder.
  ///
  void _onOkResult(OkLogResult r) {
    if (_disposed) return;
    _okResult = r;
    _takenForResult = _takenBy(r);
    if (r.complete) _useUpTaken();
    final id = r.analysisId;
    notifyListeners();
    // Not awaited: the mix just used may be new to the chips.
    if (id != null) unawaited(_loadMixOptions());
    if (id != null && r.setupUsed?.setup.residual == true) {
      unawaited(_residualPressed(id));
    }
  }

  /// A residual press saved [id]: its gas, as stored, fills the Blend tab's
  /// residual ([onResidualSaved]); a read that fails leaves the tab alone.
  Future<void> _residualPressed(String id) async {
    final GasAnalysis? stored;
    try {
      stored = await _readStored(id);
    } catch (e) {
      debugPrint('Log on OK: reading the residual entry back failed: $e');
      return;
    }
    // A late press is saved as a plain analysis whatever the setup said.
    if (_disposed || stored == null || !stored.isResidual) return;
    // Back to a fill, as after a manual residual save.
    setResidual(false);
    onResidualSaved?.call(
      stored.o2Percent,
      stored.hePercent,
      stored.fillPressureBar,
    );
  }

  /// The per-cylinder fields [r]'s own press took, or null when it did not
  /// get as far as a setup. They come with the result: presses queue up, and
  /// by the time a result arrives the provider may have been asked for the
  /// next press already.
  static ({String? cylinderId, double? pressure, String notes})? _takenBy(
    OkLogResult r,
  ) {
    final used = r.setupUsed?.setup;
    if (used == null) return null;
    return (
      cylinderId: used.cylinderId,
      pressure: used.fillPressureBar,
      notes: used.notes ?? '',
    );
  }

  /// Puts the per-cylinder fields the kept result's press took back to their
  /// start, the ones still as it took them: no cylinder, the fill pressure
  /// "Fill pressure starts at", and the notes empty and folded. A pressure
  /// that is not a number now was not what the press took. The caller
  /// notifies the listeners.
  void _useUpTaken() {
    final taken = _takenForResult;
    _takenForResult = null;
    if (taken == null) return;
    if (_knownCylinderId == taken.cylinderId) _cylinderId = null;
    final pressure = parseFillPressure(fillPressure.text);
    if (pressure.valid && pressure.bar == taken.pressure) {
      fillPressure.text = _startPressure();
    }
    if (notes.text == taken.notes) {
      notes.clear();
      _notesOpen = false;
    }
  }

  /// The stored entry [id], or null when it is gone.
  Future<GasAnalysis?> _readStored(String id) async =>
      (await _dao.list()).where((x) => x.id == id).firstOrNull;

  /// "Edit" on [okResult]: the sheet on the entry as stored, so changes made
  /// since (a sign-off from the log, a sync) are in it. Afterwards the result
  /// follows the entry as stored: signed off, here or elsewhere, it is a
  /// plain "Saved" and the press counts as complete. Printing after a
  /// sign-off is left to the log, so the sheet does not offer it.
  Future<void> editResult(BuildContext context) async {
    final r = _okResult;
    final id = r?.analysisId;
    if (r == null || id == null || _okBusy) return;
    _okBusy = true;
    notifyListeners();
    try {
      final messenger = ScaffoldMessenger.of(context);
      final List<GasAnalysis> log;
      try {
        log = await _dao.list();
      } catch (e) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
            SnackBar(content: Text('Could not open the analysis: $e')));
        return;
      }
      if (_disposed || !context.mounted) return;
      final stored = log.where((x) => x.id == id).firstOrNull;
      if (stored == null) {
        if (identical(_okResult, r)) _okResult = null;
        notifyListeners();
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
            const SnackBar(content: Text('This analysis was deleted.')));
        return;
      }
      final name = analysedBy.text.trim();
      final outcome = await showAnalysisEditSheet(
        context,
        dao: _dao,
        analysis: stored,
        mixOptions: recentDesiredMixes(log, blendTarget: _open.firstOrNull?.target),
        suggestedAnalysedBy: name.isEmpty ? null : name,
      );
      if (_disposed || !context.mounted) return;
      if (outcome == AnalysisEditOutcome.cancelled) return;
      messenger.hideCurrentSnackBar();
      if (outcome == AnalysisEditOutcome.deleted) {
        if (identical(_okResult, r)) _okResult = null;
        notifyListeners();
        messenger.showSnackBar(
          SnackBar(content: Text('Deleted ${stored.mixName} analysis.')),
        );
        return;
      }
      // The entry as the edit left it, not as it was opened.
      final GasAnalysis? after;
      try {
        after = await _readStored(id);
      } catch (e) {
        debugPrint('Analysis save card: reading the edited entry failed: $e');
        return;
      }
      if (_disposed || !context.mounted || !identical(_okResult, r)) return;
      if (after == null) {
        _okResult = null;
        notifyListeners();
      } else if (!r.complete && !after.needsSignoff) {
        // Signed off: nothing is left to do for this entry, so its press
        // counts as complete, uses up what it took and closes its blend.
        _useUpTaken();
        final blends = _openBlends;
        if (blends != null) {
          await closeBlendOnSignOff(
              signedOff: after, openBlends: blends, analyses: _dao);
          if (_disposed || !identical(_okResult, r)) return;
        }
        _okResult = OkLogResult(
          code: r.code == FeedbackCode.printed
              ? FeedbackCode.printed
              : FeedbackCode.saved,
          text: after.mixName,
          analysisId: id,
          complete: true,
          setupUsed: r.setupUsed,
        );
        notifyListeners();
      }
    } finally {
      if (!_disposed) {
        _okBusy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // Not awaited, like the logger's: see [_unbindLogger].
    unawaited(_openSub?.cancel());
    _openSub = null;
    _unbindLogger();
    fillPressure.removeListener(_onFillPressure);
    analysedBy.dispose();
    analysedFor.dispose();
    fillPressure.dispose();
    notes.dispose();
    super.dispose();
  }
}
