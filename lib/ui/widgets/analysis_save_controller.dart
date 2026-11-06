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
/// For cylinder labels the diver can also state the desired mix and the gas
/// role. "Save & print" saves the analysis and then prints its label. A hard
/// mismatch with the desired mix is confirmed before anything is saved; a
/// print that fails leaves the analysis saved.
///
/// With a [UsbOkLogger] bound (Log on OK over USB) the form is the setup for
/// the OK presses: its fields are what the next OK press saves ([okSetup]),
/// and the outcome of each press is kept in [okResult] for Edit and Delete.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../analysis/fill_pressure.dart';
import '../../analysis/gas_naming.dart';
import '../../analysis/mix_match.dart';
import '../../analyzer/bridge/bridge_protocol.dart';
import '../../analyzer/bridge/record_to_analysis.dart';
import '../../analyzer/protocol/analyzer_reading.dart';
import '../../analyzer/stability.dart';
import '../../analyzer/usb_ok_logger.dart';
import '../../data/db/gas_analyses_dao.dart';
import '../../labels/label_print_service.dart';
import '../notifiers/settings_notifier.dart';
import 'analysis_edit_sheet.dart';
import 'label_print_controls.dart';
import 'mix_mismatch_dialog.dart';

class AnalysisSaveController extends ChangeNotifier {
  /// "Analysed by" starts with the name remembered in [settings] from the
  /// last session, and "Print label on OK" with the choice remembered
  /// there. Both are read once, here.
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
        analysedBy =
            TextEditingController(text: settings.analyzerAnalysedBy ?? '') {
    _toldAnalysedBy = _analysedByNow;
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

  /// The Blend tab's target, when the diver used it recently; offered first
  /// among the desired mixes.
  DesiredMix? get blendTarget => _blendTarget;

  /// The recent Blend target that a complete save has not used yet.
  DesiredMix? get unusedBlendTarget => _unusedBlendTarget;

  /// The analyzer is connected.
  bool get connected => _connected;

  /// Takes the screen's live values. A new Blend target reloads the mix
  /// options, as the form outlives visits to the Blend tab.
  void update({
    AnalyzerReading? reading,
    required ReadingStability stability,
    DesiredMix? blendTarget,
    DesiredMix? unusedBlendTarget,
    required bool connected,
  }) {
    final targetChanged = blendTarget != _blendTarget;
    final changed = reading != _reading ||
        stability != _stability ||
        targetChanged ||
        unusedBlendTarget != _unusedBlendTarget ||
        connected != _connected;
    _reading = reading;
    _stability = stability;
    _blendTarget = blendTarget;
    _unusedBlendTarget = unusedBlendTarget;
    _connected = connected;
    if (targetChanged) unawaited(_loadMixOptions());
    if (changed) notifyListeners();
  }

  // ── Form state ──────────────────────────────────────────────────
  List<CylinderChoice> _cylinders = const [];
  String? _cylinderId;
  List<DesiredMix> _mixOptions = const [];
  DesiredMix? _desired;
  GasRole _role = GasRole.bailout;
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

  /// The desired mixes to offer: the Blend target, then the log's recent
  /// ones.
  List<DesiredMix> get mixOptions => _mixOptions;
  DesiredMix? get desiredMix => _desired;
  GasRole get role => _role;
  int get copies => _copies;

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

  /// "Desired mix" chips: a pick, or none.
  void pickMix(DesiredMix? mix) {
    _desired = mix;
    notifyListeners();
  }

  /// The diver flips the gas role.
  void tapRole(GasRole role) {
    _role = role;
    notifyListeners();
  }

  /// A new cylinder sets the role to its default; the diver can flip it.
  void selectCylinder(String? id) {
    _cylinderId = id;
    _role = gasRoleForCylinderRole(_cylinder(id)?.role);
    notifyListeners();
  }

  void setCopies(int copies) {
    _copies = copies;
    notifyListeners();
  }

  CylinderChoice? _cylinder(String? id) =>
      _cylinders.where((c) => c.id == id).firstOrNull;

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

  /// Loads [mixOptions]. Reloaded after each save, so the mix just used
  /// (perhaps typed in through "Other…") is one tap away for the next
  /// cylinder. A failed read keeps the options there are.
  Future<void> _loadMixOptions() async {
    final List<GasAnalysis> log;
    try {
      log = await _dao.list();
    } catch (e) {
      debugPrint('Analysis save card: loading the recent mixes failed: $e');
      return;
    }
    if (_disposed) return;
    _mixOptions = recentDesiredMixes(log, blendTarget: _blendTarget);
    notifyListeners();
  }

  // ── Analysed by ─────────────────────────────────────────────────

  /// The "Analysed by" the settings were last given, so they hear of a
  /// change once.
  String? _toldAnalysedBy;

  /// The "Analysed by" text, null when blank.
  String? get _analysedByNow => _blankToNull(analysedBy.text);

  /// Writes the "Analysed by" name to the settings when it changed since
  /// it was last written: when the edit ends (Done, leaving the field),
  /// when an OK press takes the setup and when a Save is made. Not on every
  /// keystroke, as it is a setting that the whole app listens to.
  void rememberAnalysedBy() {
    final name = _analysedByNow;
    if (name == _toldAnalysedBy) return;
    _toldAnalysedBy = name;
    unawaited(_settings.setAnalyzerAnalysedBy(name));
  }

  static String? _blankToNull(String s) => s.trim().isEmpty ? null : s;

  // ── Manual save ─────────────────────────────────────────────────

  /// "Save analysis", and with [print] "Save & print". Confirms an
  /// unstable reading and, before printing, a hard mismatch with the
  /// desired mix; then saves; then prints what was saved. A failed save
  /// prints nothing. A failed print leaves the analysis saved, and its
  /// Retry only prints. [context] shows the dialogs and the SnackBars; the
  /// save stops when it is gone.
  Future<void> save(BuildContext context, {bool print = false}) async {
    final printTo = print ? _labelPrinting : null;
    final gas = usableGas;
    final pressure = parseFillPressure(fillPressure.text);
    // The guard goes up before the first await, so a second tap while a
    // dialog opens or the save runs can't save the reading twice.
    if (gas == null || busy || !pressure.valid) return;
    rememberAnalysedBy();
    _saving = true;
    notifyListeners();
    try {
      // Snapshot before any await: the reading keeps updating at 1 Hz.
      final reading = _reading!;
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
        desiredMix: _desired,
        gasRole: _role,
      );
      final copies = _copies;
      final messenger = ScaffoldMessenger.of(context);
      if (!analysis.stable && !await _confirmUnstable(context)) return;
      if (_disposed || !context.mounted) return;
      if (printTo != null && !await _confirmMix(context, analysis)) return;
      if (_disposed || !context.mounted) return;
      final saved = await _add(analysis, messenger);
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
        await Scrollable.ensureVisible(
          mixRow,
          duration: const Duration(milliseconds: 300),
        );
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
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
      return null;
    }
    final saved = GasAnalysis.fromNew(id, a,
        cylinderLabel: _cylinder(a.cylinderId)?.label);
    if (_disposed) return saved;
    // Keep cylinder and diver for the next fill. The per-fill fields clear,
    // and the desired mix, role and copies start over: up to a red match
    // the label prints the desired name, so a mix left picked would label
    // the next cylinder with it. A print still uses [saved] and the copies
    // taken with it, the snapshot. In Log on OK mode they are the setup of
    // the next OK press and stay, as a press that saves them leaves them.
    if (_okLogger == null) {
      _desired = null;
      _role = gasRoleForCylinderRole(_cylinder(_cylinderId)?.role);
      _copies = 1;
      notifyListeners();
    }
    // Not awaited: the print needn't wait for the chips.
    unawaited(_loadMixOptions());
    fillPressure.clear();
    notes.clear();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text('Saved ${gasMixName(a.o2Percent, a.hePercent)} to the '
          'analysis log${a.stable ? '' : ' (not stable)'}.'),
    ));
    return saved;
  }

  // ── Log on OK ───────────────────────────────────────────────────
  UsbOkLogger? _okLogger;
  StreamSubscription<OkLogResult>? _okSub;

  /// The latest OK press of this logger, shown with Edit and Delete.
  OkLogResult? _okResult;

  /// Edit or Delete of the result is under way.
  bool _okBusy = false;

  /// "Print label on OK"; it counts only while a printer is set up.
  bool _printOnOk;

  /// The per-cylinder fields the press of [_okResult] took (from the setup
  /// it carries), for it to use up: by itself when it saved complete, or from
  /// a sign-off on the result row. Only the fields still as they were are
  /// cleared, because the diver may already be typing for the next cylinder
  /// while the label prints. Null once used up.
  ({String? cylinderId, double? pressure, String notes})? _takenForResult;

  /// A Log on OK logger is bound: the form is the setup of its OK presses.
  bool get okMode => _okLogger != null;
  OkLogResult? get okResult => _okResult;

  /// Edit or Delete of [okResult] is under way.
  bool get okBusy => _okBusy;

  /// "Print label on OK", as the diver set it; it counts only while a
  /// printer is set up.
  bool get printOnOk => _printOnOk;

  /// The diver flips "Print label on OK"; it is remembered in the settings.
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
  OkSetup okSetup() {
    rememberAnalysedBy();
    final printReady = this.printReady;
    final pressure = parseFillPressure(fillPressure.text);
    return (
      setup: LogOnOkSetup(
        analysedBy: analysedBy.text,
        desiredMix: _desired,
        gasRole: _role,
        analysedFor: _blankToNull(analysedFor.text),
        printOnOk: printReady && _printOnOk,
        printerConfigured: printReady,
        cylinderId: _knownCylinderId,
        fillPressureBar: pressure.bar,
        notes: notes.text,
        modPpo2s: _settings.analyzerModPpo2s,
      ),
      copies: _copies,
    );
  }

  /// Keeps the outcome of an OK press. One that saved complete uses up the
  /// per-cylinder fields; a press that needs sign-off leaves them, so OK on
  /// the same cylinder again still has them. The name, desired mix, role,
  /// "for", copies and print switch stay for the next cylinder.
  void _onOkResult(OkLogResult r) {
    if (_disposed) return;
    _okResult = r;
    _takenForResult = _takenBy(r);
    if (r.complete) _useUpTaken();
    notifyListeners();
    // Not awaited: the mix just used may be new to the chips.
    if (r.analysisId != null) unawaited(_loadMixOptions());
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

  /// Clears the per-cylinder fields the kept result's press took, the ones
  /// still as it took them. A pressure that is not a number now was not what
  /// the press took. The caller notifies the listeners.
  void _useUpTaken() {
    final taken = _takenForResult;
    _takenForResult = null;
    if (taken == null) return;
    if (_knownCylinderId == taken.cylinderId) _cylinderId = null;
    final pressure = parseFillPressure(fillPressure.text);
    if (pressure.valid && pressure.bar == taken.pressure) fillPressure.clear();
    if (notes.text == taken.notes) notes.clear();
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
        // counts as complete and uses up what it took.
        _useUpTaken();
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

  /// "Delete" on [okResult]: a confirm, then the entry is soft-deleted.
  Future<void> deleteResult(BuildContext context) async {
    final r = _okResult;
    final id = r?.analysisId;
    if (r == null || id == null || _okBusy) return;
    _okBusy = true;
    notifyListeners();
    try {
      final messenger = ScaffoldMessenger.of(context);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete this analysis?'),
          content: const Text('It is removed from the analysis log.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('analysis-ok-delete-confirm'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await _dao.softDelete(id);
      } catch (e) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
        return;
      }
      if (_disposed || !context.mounted) return;
      if (identical(_okResult, r)) _okResult = null;
      notifyListeners();
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('Analysis deleted.')));
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
    // A name still being typed (a touch outside the field doesn't end the
    // edit on a phone). Written once the tree is done, not while it is torn
    // down, because the screen listens to what it changes.
    final name = _analysedByNow;
    if (name != _toldAnalysedBy) {
      final settings = _settings;
      scheduleMicrotask(() => settings.setAnalyzerAnalysedBy(name));
    }
    fillPressure.removeListener(_onFillPressure);
    analysedBy.dispose();
    analysedFor.dispose();
    fillPressure.dispose();
    notes.dispose();
    super.dispose();
  }
}
