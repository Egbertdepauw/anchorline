/// Cylinder analysis log (issue #111): saved gas-analyzer readings,
/// newest first, optionally narrowed to one cylinder. Swipe to delete
/// (soft delete, synced). The app-bar action exports the shown entries
/// as CSV through the system share sheet.
///
/// Cylinder labels (issue #114): each entry shows its desired mix and how
/// far the analysis is off it, and a "DIL" marker for diluent. Tap an entry
/// to edit what the diver stated (desired mix, gas role, analysed by, for,
/// cylinder, fill pressure, notes), or to delete it. With a label printer
/// set up, each entry has a print action: copies, then the hard-mismatch
/// warning when it applies, then the print.
///
/// An entry that needs sign-off (issue #113, Log on OK) carries a "Needs
/// sign-off" badge and has no print action until it is signed off, which
/// the edit sheet does ("Sign off", or "Sign off and print" through the
/// print action's own checks). A line above the list counts them, and a
/// filter chip narrows the list to them.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../analysis/mix_match.dart';
import '../../data/db/gas_analyses_dao.dart';
import '../../data/models/gas_analysis_csv.dart';
import '../../labels/label_print_service.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';
import '../widgets/analysis_edit_sheet.dart';
import '../widgets/label_print_controls.dart';
import '../widgets/mix_match_indicator.dart';
import '../widgets/mix_mismatch_dialog.dart';

/// Hands a finished CSV to the user. [origin] anchors the iPad / macOS
/// share popover.
typedef CsvSharer = Future<void> Function(
    String csv, String fileName, Rect? origin);

/// Default [CsvSharer]: writes the file to the temp dir and opens the
/// share sheet, the same path the other file exports use.
Future<void> shareCsvFile(String csv, String fileName, Rect? origin) async {
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, fileName));
  await file.writeAsString(csv);
  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'text/csv', name: fileName)],
    subject: 'Anchorline gas analyses',
    sharePositionOrigin: origin,
  );
}

class GasAnalysisLogScreen extends StatefulWidget {
  const GasAnalysisLogScreen({
    super.key,
    required this.dao,
    this.cylinderId,
    this.cylinderLabel,
    this.shareCsv = shareCsvFile,
    this.labelPrinting,
  });

  final GasAnalysesDaoLike dao;

  /// When set, only this cylinder's analyses are listed.
  final String? cylinderId;

  /// Shown in the title when [cylinderId] is set.
  final String? cylinderLabel;

  final CsvSharer shareCsv;

  /// Reprints an entry's label. With a printer set up each entry gets a
  /// print action; without one, or when null, none.
  final LabelPrintService? labelPrinting;

  @override
  State<GasAnalysisLogScreen> createState() => _GasAnalysisLogScreenState();
}

class _GasAnalysisLogScreenState extends State<GasAnalysisLogScreen> {
  static final _dateFormat = DateFormat('d MMM yyyy, HH:mm');

  List<GasAnalysis>? _items;
  StreamSubscription<void>? _changes;

  /// Entries with a reprint under way, from the copies prompt until the
  /// printer has answered. Their print action is off meanwhile.
  final Set<String> _reprinting = {};

  /// The "Show only these" filter of the sign-off line is on.
  bool _onlyNeedsSignoff = false;

  @override
  void initState() {
    super.initState();
    _reload();
    _changes = widget.dao.watchChanges().listen((_) => _reload());
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  /// Reads the log and shows it. Returns what was read.
  Future<List<GasAnalysis>> _reload() async {
    final items = await widget.dao.list(cylinderId: widget.cylinderId);
    if (mounted) {
      setState(() {
        _items = items;
        // With nothing left to filter to the filter goes too, so it does
        // not come back on its own when an entry is flagged again.
        if (!items.any((a) => a.needsSignoff)) _onlyNeedsSignoff = false;
      });
    }
    return items;
  }

  /// The entry [id] as stored now, or null when it was deleted. Refreshes
  /// the list on the way.
  Future<GasAnalysis?> _stored(String id) async =>
      (await _reload()).where((x) => x.id == id).firstOrNull;

  /// What the list shows of [items]: all of them, or only those that need
  /// sign-off while the filter is on. The filter does nothing when none do.
  List<GasAnalysis> _shown(List<GasAnalysis> items) {
    if (!_onlyNeedsSignoff) return items;
    final flagged = items.where((a) => a.needsSignoff).toList();
    return flagged.isEmpty ? items : flagged;
  }

  /// Shows [kSignOffBeforePrintMessage] in place of the SnackBar that is up
  /// when [a] still needs sign-off. True when it does: the caller stops.
  ///
  /// The print service refuses such an entry too, but its failure bar
  /// offers a Retry that could never succeed; this one has none.
  bool _refuseUnsigned(GasAnalysis a) {
    if (!a.needsSignoff) return false;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text(kSignOffBeforePrintMessage)),
      );
    return true;
  }

  /// The name to start an empty "Analysed by" with: the newest non-blank
  /// one in the loaded list.
  String? _suggestedAnalysedBy() {
    for (final a in _items ?? const <GasAnalysis>[]) {
      final name = a.analysedBy?.trim();
      if (name != null && name.isNotEmpty) return name;
    }
    return null;
  }

  /// Opens the edit sheet for [a], offering the recent desired mixes of the
  /// list. Returns what the sheet did; [AnalysisEditOutcome.cancelled] when
  /// nothing changed.
  ///
  /// Any change also takes down the SnackBar that is up: a print failure's
  /// Retry there was offered for the entry as it was before the edit. A
  /// delete says so, as the swipe does.
  Future<AnalysisEditOutcome> _openEditSheet(GasAnalysis a) async {
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await showAnalysisEditSheet(
      context,
      dao: widget.dao,
      analysis: a,
      mixOptions: recentDesiredMixes(_items ?? const []),
      suggestedAnalysedBy: _suggestedAnalysedBy(),
      canPrint: widget.labelPrinting?.isConfigured == true,
    );
    if (outcome != AnalysisEditOutcome.cancelled) {
      messenger.hideCurrentSnackBar();
    }
    if (outcome == AnalysisEditOutcome.deleted) _announceDeleted(messenger, a);
    return outcome;
  }

  /// Tapping an entry. "Sign off and print" prints the entry as stored after
  /// the sign-off, through [_reprint] and its checks.
  Future<void> _edit(GasAnalysis a) async {
    final outcome = await _openEditSheet(a);
    if (outcome == AnalysisEditOutcome.cancelled) return;
    final stored = await _stored(a.id);
    if (outcome != AnalysisEditOutcome.signOffAndPrint) return;
    // Deleted meanwhile, or flagged again (through sync): nothing to print.
    // Say so now, not after the copies prompt.
    if (stored == null || !mounted || _refuseUnsigned(stored)) return;
    await _reprint(stored);
  }

  /// Prints the label of [a]: asks for copies, then, on a hard mismatch
  /// with the desired mix, whether to print the analysed mix. "Change
  /// desired mix" opens the edit sheet; after a save the entry is read
  /// back as stored and checked again, with the copies already chosen.
  ///
  /// The entry is read back after every prompt (copies, the mismatch
  /// dialog's "Print as ...", the edit sheet), since it can be edited or
  /// deleted (here or through sync) while the prompt is up. The label is
  /// always of the entry as stored; a deleted entry is not printed, and
  /// neither is one that needs sign-off by then (the SnackBar says so). If
  /// the mix or role changed while the mismatch dialog was up, it is graded
  /// and asked about again. A Retry of a failed print reads it back again.
  Future<void> _reprint(GasAnalysis a) async {
    final service = widget.labelPrinting;
    // The guard goes up before the first await, so a double tap can't
    // start a second reprint of the same entry.
    if (service == null || _reprinting.contains(a.id)) return;
    setState(() => _reprinting.add(a.id));
    try {
      final copies = await showCopiesDialog(context);
      if (copies == null || !mounted) return;
      final current = await _stored(a.id);
      if (current == null || !mounted) return;
      if (_refuseUnsigned(current)) return;
      var entry = current;
      while (entry.match?.level == MixMatchLevel.hard) {
        final choice = await showMixMismatchDialog(context, analysis: entry);
        if (!mounted || choice == MismatchChoice.cancel) return;
        final printAnalysed = choice == MismatchChoice.printAnalysed;
        if (!printAnalysed &&
            await _openEditSheet(entry) == AnalysisEditOutcome.cancelled) {
          return;
        }
        // The dialog or the sheet was up for a while: the entry can be
        // flagged, deleted or changed (through sync) meanwhile.
        final stored = await _stored(entry.id);
        if (stored == null || !mounted) return;
        if (_refuseUnsigned(stored)) return;
        // "Print as ..." answers for the mix and role the dialog showed.
        // If they changed, the loop grades and asks again.
        final answered = printAnalysed &&
            stored.desiredMix == entry.desiredMix &&
            stored.gasRole == entry.gasRole;
        entry = stored;
        if (answered) break;
      }
      // The Retry may run after this screen is gone, so it reads through
      // the DAO, not the screen.
      final dao = widget.dao;
      final id = entry.id;
      await printWithFeedback(
        context,
        service: service,
        analysis: entry,
        copies: copies,
        reload: () async =>
            (await dao.list()).where((x) => x.id == id).firstOrNull,
      );
    } finally {
      _reprinting.remove(a.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _delete(GasAnalysis a) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _items = [...?_items]..removeWhere((x) => x.id == a.id));
    await widget.dao.softDelete(a.id);
    _announceDeleted(messenger, a);
    await _reload();
  }

  /// "Deleted EAN32 analysis." Replaces what is up. A print failure stays
  /// until dismissed, so this would queue behind it unseen, and its Retry
  /// could be for this entry.
  void _announceDeleted(ScaffoldMessengerState messenger, GasAnalysis a) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text('Deleted ${a.mixName} analysis.')),
    );
  }

  Future<void> _export() async {
    final all = _items;
    if (all == null || all.isEmpty) return;
    final items = _shown(all);
    final messenger = ScaffoldMessenger.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box != null ? box.localToGlobal(Offset.zero) & box.size : null;
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    try {
      await widget.shareCsv(
          gasAnalysesToCsv(items), 'gas-analyses-$date.csv', origin);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final title = widget.cylinderId == null
        ? 'Analysis log'
        : 'Analyses · ${widget.cylinderLabel ?? 'Cylinder'}';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            key: const ValueKey('analysis-log-export'),
            tooltip: 'Export CSV',
            icon: const Icon(Icons.ios_share),
            onPressed: items == null || items.isEmpty ? null : _export,
          ),
        ],
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? _empty(context)
              : _list(context, items),
    );
  }

  Widget _list(BuildContext context, List<GasAnalysis> items) {
    final needSignoff = items.where((a) => a.needsSignoff).length;
    final shown = _shown(items);
    final list = ListView.separated(
      itemCount: shown.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: context.palette.surfaceRaised),
      itemBuilder: (context, i) => _tile(context, shown[i]),
    );
    if (needSignoff == 0) return list;
    return Column(
      children: [
        _signoffLine(context, needSignoff),
        Expanded(child: list),
      ],
    );
  }

  /// "2 analyses need sign-off" and the chip that narrows the list to them.
  Widget _signoffLine(BuildContext context, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg, vertical: Spacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              count == 1
                  ? '1 analysis needs sign-off'
                  : '$count analyses need sign-off',
              key: const ValueKey('analysis-log-signoff-count'),
              style: AppTypography.body
                  .copyWith(color: context.palette.textPrimary),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          FilterChip(
            key: const ValueKey('analysis-log-signoff-filter'),
            label: const Text('Show only these'),
            selected: _onlyNeedsSignoff,
            onSelected: (on) => setState(() => _onlyNeedsSignoff = on),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Text(
            widget.cylinderId == null
                ? 'No analyses saved yet. Save a reading from the gas '
                    'analyzer to start the log.'
                : 'No analyses for this cylinder yet.',
            textAlign: TextAlign.center,
            style: AppTypography.body
                .copyWith(color: context.palette.textMuted),
          ),
        ),
      );

  Widget _tile(BuildContext context, GasAnalysis a) {
    final palette = context.palette;
    final desired = a.desiredMix;
    final diluent = a.gasRole == GasRole.diluent;
    final printing = widget.labelPrinting;
    // An entry that needs sign-off never prints a label until signed off.
    final canPrint =
        printing != null && printing.isConfigured && !a.needsSignoff;
    final details = <String>[
      _dateFormat.format(a.analysedAt),
      if (widget.cylinderId == null && a.cylinderDisplay != null)
        a.cylinderDisplay!,
      if (a.analysedBy != null) a.analysedBy!,
      if (a.fillPressureBar != null)
        '${a.fillPressureBar!.toStringAsFixed(0)} bar',
    ];
    return Dismissible(
      key: ValueKey('analysis-${a.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: SafetyColors.danger,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        child: Icon(Icons.delete_outline, color: palette.textPrimary),
      ),
      onDismissed: (_) => _delete(a),
      child: ListTile(
        onTap: () => _edit(a),
        leading: Tooltip(
          message: a.stable ? 'Stable reading' : 'Saved before stable',
          child: Icon(
            a.stable ? Icons.check_circle : Icons.warning_amber_rounded,
            color: a.stable ? SafetyColors.success : SafetyColors.warning,
          ),
        ),
        title: Text(
          a.mixName,
          style: AppTypography.title.copyWith(color: palette.textPrimary),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (a.needsSignoff || diluent || desired != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.xs),
                child: Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (a.needsSignoff)
                      _Marker(
                        key: ValueKey('analysis-needs-signoff-${a.id}'),
                        label: 'Needs sign-off',
                        color: SafetyColors.warning,
                      ),
                    if (diluent)
                      _Marker(
                        key: ValueKey('analysis-dil-${a.id}'),
                        label: 'DIL',
                        color: palette.accentPrimary,
                      ),
                    if (desired != null)
                      Text(
                        'Desired ${desired.name}',
                        style: AppTypography.body
                            .copyWith(color: palette.textPrimary),
                      ),
                  ],
                ),
              ),
            // Grading NaN throws; a stored analysis is finite, but a row
            // from elsewhere is not worth a crash.
            if (desired != null &&
                a.o2Percent.isFinite &&
                a.hePercent.isFinite)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.xs),
                child: MixMatchIndicator(
                  o2Percent: a.o2Percent,
                  hePercent: a.hePercent,
                  desired: desired,
                ),
              ),
            Text(
              details.join(' · '),
              style:
                  AppTypography.body.copyWith(color: palette.textSecondary),
            ),
          ],
        ),
        trailing: a.notes == null && !canPrint
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (a.notes != null)
                    Tooltip(
                      message: a.notes!,
                      child: Icon(Icons.notes, color: palette.textMuted),
                    ),
                  if (canPrint)
                    IconButton(
                      key: ValueKey('analysis-print-${a.id}'),
                      tooltip: 'Print label',
                      icon: const Icon(Icons.print_outlined),
                      onPressed: _reprinting.contains(a.id)
                          ? null
                          : () => _reprint(a),
                    ),
                ],
              ),
      ),
    );
  }
}

/// A small outlined tag on an entry: "DIL" on a diluent entry (bailout and
/// deco entries have none), "Needs sign-off" on one that is not signed off.
class _Marker extends StatelessWidget {
  const _Marker({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xs + 2),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: Radii.chipBr,
      ),
      child: Text(
        label,
        style: AppTypography.label.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
