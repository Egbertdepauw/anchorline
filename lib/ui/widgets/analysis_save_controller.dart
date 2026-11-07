/// The state and logic of the "Save analysis" form on the gas-analyzer
/// screen (issues #111, #113, #114), apart from the widgets that show it, so
/// the form and its actions can be separate widgets that share one state.
///
/// The analyzer screen owns the controller while it shows the form, and
/// tells it the live reading, the Blend target, the connection and the Log
/// on OK logger on every build ([update], [bindLogger]). The form's widgets
/// listen to it and call its actions.
///
/// It captures the current reading plus the diver's context (cylinder from
/// Equipment, who analysed, fill pressure, notes) into the synced cylinder
/// analysis log. A reading that isn't STABLE asks for confirmation first;
/// it's never blocked, because a diver at the fill station sometimes has to
/// log what they've got.
///
/// For cylinder labels the form also holds the desired mix and the gas role.
/// The desired mix is picked automatically (spec §4.3): the unused Blend
/// target or the nearest standard mix, and only when it grades match or
/// orange against the reading, because up to a red match the label prints
/// its name. A chip the diver taps is their pick until the next manual save.
/// The role follows the rule of [resolveGasRole]: a tapped role, else the
/// picked cylinder's, else Bailout / deco above 30 % O2. "Save & print"
/// saves the analysis and then prints its label. A hard mismatch with the
/// desired mix is confirmed before anything is saved; a print that fails
/// leaves the analysis saved.
///
/// With a [UsbOkLogger] bound (Log on OK over USB) the form is the setup for
/// the OK presses: its fields are what the next OK press saves ([okSetup]),
/// and the outcome of each press is kept in [okResult] for Edit.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../analysis/fill_pressure.dart';
import '../../analysis/gas_naming.dart';
import '../../analysis/mix_match.dart';
import '../../analysis/standard_mix_pick.dart';
import '../../analyzer/bridge/bridge_protocol.dart';
import '../../analyzer/bridge/record_to_analysis.dart';
import '../../analyzer/protocol/analyzer_reading.dart';
import '../../analyzer/stability.dart';
import '../../analyzer/usb_ok_logger.dart';
import '../../data/db/gas_analyses_dao.dart';
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
    DateTime Function() now = DateTime.now,
  })  : _dao = dao,
        _settings = settings,
        _labelPrinting = labelPrinting,
        _now = now,
        _printOnOk = settings.analyzerPrintOnOk,
        analysedBy = TextEditingController(text: settings.yourInitials ?? '') {
    fillPressure.text = _startPressure();
    _seenFillPressure = fillPressure.text;
    fillPressure.addListener(_onFillPressure);
    unawaited(_loadCylinders());
    unawaited(_loadMixOptions());
  }

  final GasAnalysesDaoLike _dao;
  final SettingsNotifier _settings;
  final LabelPrintService? _labelPrinting;

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
  DesiredMix? _blendTarget;
  DesiredMix? _unusedBlendTarget;
  bool _connected = false;

  /// The live reading to save; null before the first one.
  AnalyzerReading? get reading => _reading;
  ReadingStability get stability => _stability;

  /// The Blend tab's target, when the diver used it recently; offered among
  /// the desired mixes right after the selected one.
  DesiredMix? get blendTarget => _blendTarget;

  /// The recent Blend target that a complete save has not used yet; the
  /// automatic pick prefers it.
  DesiredMix? get unusedBlendTarget => _unusedBlendTarget;

  /// The analyzer is connected.
  bool get connected => _connected;

  /// Called after a complete manual save of the Blend target, or the
  /// sign-off of an OK press of it, so the target is used up (one blend is
  /// one cylinder). An OK press that saves complete is marked by the
  /// session. The screen sets it to `BlendNotifier.markRecentTargetUsed`.
  VoidCallback? onBlendTargetUsed;

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
    DesiredMix? blendTarget,
    DesiredMix? unusedBlendTarget,
    required bool connected,
  }) {
    final changed = reading != _reading ||
        stability != _stability ||
        blendTarget != _blendTarget ||
        unusedBlendTarget != _unusedBlendTarget ||
        connected != _connected;
    final connecting = connected && !_connected;
    _reading = reading;
    _stability = stability;
    _blendTarget = blendTarget;
    _unusedBlendTarget = unusedBlendTarget;
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
  /// phone: the selected mix, then the Blend target, then the log's recent
  /// desired mixes, with no duplicates.
  List<DesiredMix> get mixOptions {
    final out = <DesiredMix>[];
    void add(DesiredMix? m) {
      if (m != null && out.length < _kMaxMixChips && !out.contains(m)) {
        out.add(m);
      }
    }

    add(desiredMix);
    add(_blendTarget);
    _recentMixes.forEach(add);
    return out;
  }

  static const _kMaxMixChips = 3;

  /// The desired mix: the automatic pick for the reading, or the diver's.
  DesiredMix? get desiredMix => _mixAutomatic ? _autoPick?.mix : _diverMix;

  /// The desired mix follows the reading (no chip tapped since the last
  /// manual save).
  bool get mixIsAutomatic => _mixAutomatic;

  /// Where the automatic pick came from; null for the diver's pick and when
  /// nothing is picked.
  MixPickSource? get mixSource => _mixAutomatic ? _autoPick?.source : null;

  /// The gas role by the rule of [resolveGasRole], for [desiredMix].
  GasRole get role => _roleFor(desiredMix, usableGas?.o2);

  /// The diver tapped the role, so [role] is theirs rather than the rule's.
  bool get roleTapped => _tappedRole != null;

  /// The role for [mix] on a reading with [readingO2] % O2: the tapped role,
  /// else the picked cylinder's, else by the O2 of the mix, or of the
  /// reading when there is no mix (none at all is Diluent).
  GasRole _roleFor(DesiredMix? mix, double? readingO2) => resolveGasRole(
        tapped: _tappedRole,
        cylinderRole: _cylinder(_knownCylinderId)?.role,
        o2PercentForRule: mix?.o2Percent.toDouble() ?? readingO2 ?? 0,
      );

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

  /// The diver picks a mix with a chip or "Other…", or none (null, the
  /// selected chip tapped again). It is their pick until the next manual
  /// save.
  void pickMix(DesiredMix? mix) {
    _mixAutomatic = false;
    _diverMix = mix;
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

  /// The automatic pick for [gas]: the unused Blend target or the nearest
  /// standard mix, within orange, or null.
  MixPick? _pickFor(({double o2, double he})? gas) => gas == null
      ? null
      : pickDesiredMix(
          o2Percent: gas.o2,
          hePercent: gas.he,
          blendTarget: _unusedBlendTarget,
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
  /// automatic pick is never taken from a later line.
  Future<void> save(BuildContext context, {bool print = false}) async {
    final printTo = print ? _labelPrinting : null;
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
      final desired = _mixAutomatic ? _pickFor(gas)?.mix : _diverMix;
      final blendTarget = _blendTarget;
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
        gasRole: _roleFor(desired, gas.o2),
      );
      final copies = _copies;
      final messenger = ScaffoldMessenger.of(context);
      if (!analysis.stable && !await _confirmUnstable(context)) return;
      if (_disposed || !context.mounted) return;
      if (printTo != null && !await _confirmMix(context, analysis)) return;
      if (_disposed || !context.mounted) return;
      final saved = await _add(analysis, messenger);
      if (saved != null && desired != null && desired == blendTarget) {
        _useBlendTarget();
      }
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
  Future<GasAnalysis?> _add(
    NewGasAnalysis a,
    ScaffoldMessengerState messenger,
  ) async {
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
          'analysis log${a.stable ? '' : ' (not stable)'}.'),
    ));
    return saved;
  }

  /// A SnackBar about a save made from the action bar, floating clear of it.
  static SnackBar _clearOfBar(Widget content) => SnackBar(
        content: content,
        behavior: SnackBarBehavior.floating,
        margin: kSnackBarClearOfActionBar,
      );

  /// A completed save used the Blend target: it is not picked again (one
  /// blend is one cylinder) until the next Blend edit.
  void _useBlendTarget() {
    onBlendTargetUsed?.call();
    if (_disposed) return;
    _unusedBlendTarget = null;
    _autoPick = _pickFor(usableGas);
    notifyListeners();
  }

  // ── Log on OK ───────────────────────────────────────────────────
  UsbOkLogger? _okLogger;
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

  /// The setup of the press the unused Blend target was offered to, until
  /// that press's outcome is known. Meanwhile no other press is offered the
  /// target: presses are handled one after the other, and a press queued
  /// behind it asks for its setup before the first one's result arrives.
  LogOnOkSetup? _targetOfferedTo;

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
  void bindLogger(UsbOkLogger? logger) {
    if (identical(logger, _okLogger)) return;
    _unbindLogger();
    _okResult = null;
    _takenForResult = null;
    _targetOfferedTo = null;
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
  /// It is the logger's [UsbOkLogger.setupProvider], asked once per press,
  /// and it has one side effect: the unused Blend target goes to one press
  /// at a time. The press that gets it holds it until its outcome is known
  /// ([_onOkResult]), so a press queued behind it gets none. It writes
  /// nothing to the settings; "Analysed by" is never written back.
  OkSetup okSetup() {
    final printReady = this.printReady;
    final pressure = parseFillPressure(fillPressure.text);
    final cylinderRole = _cylinder(_knownCylinderId)?.role;
    final unused = _unusedBlendTarget;
    // A lease on an older target (the diver blended again since) is no
    // reason to keep the new one back.
    final target = _targetOfferedTo?.blendTarget == unused ? null : unused;
    final setup = LogOnOkSetup(
      analysedBy: analysedBy.text,
      desiredMix: _mixAutomatic ? null : _diverMix,
      autoPickMix: _mixAutomatic,
      blendTarget: target,
      gasRole: _tappedRole ??
          (cylinderRole == null ? null : gasRoleForCylinderRole(cylinderRole)),
      analysedFor: _blankToNull(analysedFor.text),
      printOnOk: printReady && _printOnOk,
      printerConfigured: printReady,
      cylinderId: _knownCylinderId,
      fillPressureBar: pressure.bar,
      notes: notes.text,
      modPpo2s: _settings.analyzerModPpo2s,
    );
    if (target != null) _targetOfferedTo = setup;
    return (setup: setup, copies: _copies);
  }

  /// Keeps the outcome of an OK press. One that saved complete uses up the
  /// per-cylinder fields; a press that needs sign-off leaves them, so OK on
  /// the same cylinder again still has them. The name, desired mix, tapped
  /// role, "for", copies and print switch stay for the next cylinder.
  ///
  /// Marking the Blend target used is the session's (`AnalyzerSession`),
  /// which hears every press to the end, also one that finishes after Stop
  /// or Disconnect when this form no longer listens. Here the press that
  /// held the target only lets go of it ([_releaseTarget]).
  void _onOkResult(OkLogResult r) {
    if (_disposed) return;
    _okResult = r;
    _takenForResult = _takenBy(r);
    if (r.complete) _useUpTaken();
    final id = r.analysisId;
    if (_targetOfferedTo != null &&
        identical(r.setupUsed?.setup, _targetOfferedTo)) {
      if (r.complete && id != null) {
        unawaited(_releaseTarget(id));
      } else {
        // Not saved complete: the target is still unused.
        _targetOfferedTo = null;
      }
    }
    notifyListeners();
    // Not awaited: the mix just used may be new to the chips.
    if (id != null) unawaited(_loadMixOptions());
  }

  /// The press that held the Blend target saved complete: its entry is read
  /// back, and then the target is let go of. When the entry has the target,
  /// this form stops offering it at once, not only from the screen's next
  /// build, which brings the session's used mark.
  Future<void> _releaseTarget(String id) async {
    final held = _targetOfferedTo;
    GasAnalysis? stored;
    try {
      stored = await _readStored(id);
    } catch (e) {
      debugPrint('Analysis save card: reading the OK entry failed: $e');
    }
    if (_disposed) return;
    final target = _unusedBlendTarget;
    if (stored != null && target != null && stored.desiredMix == target) {
      _unusedBlendTarget = null;
      _autoPick = _pickFor(usableGas);
      notifyListeners();
    }
    if (identical(_targetOfferedTo, held)) _targetOfferedTo = null;
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
        mixOptions: recentDesiredMixes(log, blendTarget: _blendTarget),
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
        // counts as complete and uses up what it took, the Blend target
        // included.
        _useUpTaken();
        final target = _blendTarget;
        if (target != null &&
            _unusedBlendTarget != null &&
            after.desiredMix == target) {
          _useBlendTarget();
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
    _unbindLogger();
    fillPressure.removeListener(_onFillPressure);
    analysedBy.dispose();
    analysedFor.dispose();
    fillPressure.dispose();
    notes.dispose();
    super.dispose();
  }
}
