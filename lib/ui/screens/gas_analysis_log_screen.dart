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
/// Rows are in the dive list's style (spec §5): a 3 px edge (accent for
/// diluent, muted for bailout / deco), the analysed mix in mono, a stats
/// line and a caption line saying how far it is off the desired mix. Days
/// are separated by a header.
///
/// An entry that needs sign-off (issue #113, Log on OK) carries a "Needs
/// sign-off" tag; its print action is faded and says why on tap until it is
/// signed off, which the edit sheet does ("Sign off", or "Sign off and
/// print" through the print action's own checks). A chip in the tool row
/// counts them and narrows the list to them; "All" restores it.
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
import '../widgets/mix_match_indicator.dart' show mixMatchColor;
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
    this.embedded = false,
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

  /// Shown as the Gas destination's Log tab: no app bar of its own, and the
  /// Export button sits in a row at the top of the list.
  final bool embedded;

  @override
  State<GasAnalysisLogScreen> createState() => _GasAnalysisLogScreenState();
}

class _GasAnalysisLogScreenState extends State<GasAnalysisLogScreen> {
  static final _timeFormat = DateFormat('HH:mm');
  static final _dayKeyFormat = DateFormat('yyyy-MM-dd');
  static final _dayFormat = DateFormat('d MMM yyyy');

  List<GasAnalysis>? _items;
  StreamSubscription<void>? _changes;

  /// Entries with a reprint under way, from the copies prompt until the
  /// printer has answered. Their print action is off meanwhile.
  final Set<String> _reprinting = {};

  /// The "Needs sign-off" chip of the tool row is on.
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
    final list = items == null
        ? const Center(child: CircularProgressIndicator())
        : items.isEmpty
            ? _empty(context)
            : _list(context, items);
    // The one place the tool row is built. The Log tab always has it, for
    // Export; the pushed screen has Export in its app bar, so it has the
    // row only while there are entries to filter.
    final body = widget.embedded || (items != null && items.isNotEmpty)
        ? Column(
            children: [
              _toolRow(context, items),
              Expanded(child: list),
            ],
          )
        : list;
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [_exportButton(items)],
      ),
      body: body,
    );
  }

  Widget _exportButton(List<GasAnalysis>? items) => IconButton(
        key: const ValueKey('analysis-log-export'),
        tooltip: 'Export CSV',
        icon: const Icon(Icons.ios_share),
        onPressed: items == null || items.isEmpty ? null : _export,
      );

  Widget _list(BuildContext context, List<GasAnalysis> items) {
    final shown = _shown(items);
    final rows = _rows(shown);
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        return row is DateTime
            ? _dayHeader(context, row)
            : _tile(context, row as GasAnalysis);
      },
    );
  }

  /// [items] with a day (a [DateTime] at midnight) ahead of each run of
  /// entries from the same local day.
  List<Object> _rows(List<GasAnalysis> items) {
    final rows = <Object>[];
    String? lastDay;
    for (final a in items) {
      final at = a.analysedAt.toLocal();
      final day = _dayKeyFormat.format(at);
      if (day != lastDay) {
        rows.add(DateTime(at.year, at.month, at.day));
        lastDay = day;
      }
      rows.add(a);
    }
    return rows;
  }

  /// "Today", "Yesterday", else "7 Nov 2026".
  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return 'Today';
    if (day == DateTime(today.year, today.month, today.day - 1)) {
      return 'Yesterday';
    }
    return _dayFormat.format(day);
  }

  Widget _dayHeader(BuildContext context, DateTime day) => Container(
        key: ValueKey('analysis-day-${_dayKeyFormat.format(day)}'),
        color: context.palette.surfaceRaised,
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md, vertical: Spacing.xs),
        alignment: Alignment.centerLeft,
        child: Text(
          _dayLabel(day).toUpperCase(),
          style: AppTypography.caption.copyWith(
              color: context.palette.textSecondary, letterSpacing: 1.2),
        ),
      );

  /// The filter chips ("All n" while there are entries, "Needs sign-off n"
  /// while one needs it) and, on the Log tab, Export at the right. The
  /// screen pushed from Equipment has Export in its app bar.
  Widget _toolRow(BuildContext context, List<GasAnalysis>? items) {
    final flagged = items?.where((a) => a.needsSignoff).length ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.xs),
      child: Row(
        children: [
          if (items != null && items.isNotEmpty)
            Expanded(
              child: Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.xs,
                children: [
                  FilterChip(
                    key: const ValueKey('analysis-log-filter-all'),
                    label: Text('All ${items.length}'),
                    selected: !_onlyNeedsSignoff,
                    onSelected: (_) =>
                        setState(() => _onlyNeedsSignoff = false),
                  ),
                  if (flagged > 0)
                    FilterChip(
                      key: const ValueKey('analysis-log-signoff-filter'),
                      label: Text('Needs sign-off $flagged'),
                      labelStyle: TextStyle(color: SafetyColors.warning),
                      selected: _onlyNeedsSignoff,
                      onSelected: (on) =>
                          setState(() => _onlyNeedsSignoff = on),
                    ),
                ],
              ),
            )
          else
            const Spacer(),
          if (widget.embedded) _exportButton(items),
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
    final diluent = a.gasRole == GasRole.diluent;
    final printing = widget.labelPrinting;
    final canPrint = printing != null && printing.isConfigured;
    // Bailout and deco read quieter than diluent; both are palette tokens
    // so the edge shows in every theme.
    final edge = diluent ? palette.accentPrimary : palette.textMuted;
    final monoStyle = AppTypography.readoutSm;
    final stats = <String>[
      '${a.o2Percent.toStringAsFixed(1)} / ${a.hePercent.toStringAsFixed(1)}',
      if (a.fillPressureBar != null)
        '${a.fillPressureBar!.toStringAsFixed(0)} bar',
      a.analysedBy ?? 'no name',
      if (widget.cylinderId == null && a.cylinderDisplay != null)
        a.cylinderDisplay!,
      if (a.analysedFor != null) 'for ${a.analysedFor}',
    ];
    // Grading NaN throws; a stored analysis is finite, but a row from
    // elsewhere is not worth a crash.
    final desired = a.desiredMix;
    final match = a.o2Percent.isFinite && a.hePercent.isFinite ? a.match : null;
    final caption = <Widget>[
      if (match != null && desired != null)
        Text(
          mixMatchText(match, desired.name),
          style: AppTypography.caption
              .copyWith(color: mixMatchColor(match.level)),
        ),
      if (!a.stable)
        Text(
          'Saved before stable',
          style: AppTypography.caption.copyWith(color: SafetyColors.warning),
        ),
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
      child: Container(
        decoration: BoxDecoration(
          color: palette.surfaceCard,
          border: Border(
            left: BorderSide(color: edge, width: 3),
            bottom: BorderSide(color: palette.surfaceRaised),
          ),
        ),
        child: InkWell(
          onTap: () => _edit(a),
          child: Padding(
            padding: const EdgeInsets.only(
                left: Spacing.md,
                top: Spacing.sm + 2,
                bottom: Spacing.sm + 2),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Wraps on a narrow phone or large text rather
                          // than squeezing the name.
                          Expanded(
                            child: Wrap(
                              spacing: Spacing.xs + 2,
                              runSpacing: 2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _Marker(
                                  key: ValueKey('analysis-role-${a.id}'),
                                  label: diluent ? 'DIL' : 'BO',
                                  color: diluent
                                      ? palette.accentPrimary
                                      : palette.textMuted,
                                ),
                                Text(
                                  a.mixName,
                                  style: monoStyle.copyWith(
                                      color: palette.textPrimary),
                                ),
                                if (a.needsSignoff)
                                  _Marker(
                                    key: ValueKey(
                                        'analysis-needs-signoff-${a.id}'),
                                    label: 'Needs sign-off',
                                    color: SafetyColors.warning,
                                  ),
                                if (a.notes != null)
                                  Tooltip(
                                    key: ValueKey('analysis-notes-${a.id}'),
                                    message: a.notes!,
                                    triggerMode: TooltipTriggerMode.tap,
                                    child: Icon(Icons.notes,
                                        size: 14, color: palette.textMuted),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: Spacing.sm - 2),
                          Text(
                            _timeFormat.format(a.analysedAt),
                            style: AppTypography.caption
                                .copyWith(color: palette.textMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: Spacing.xs - 2),
                      Text(
                        stats.join(' · '),
                        style: monoStyle.copyWith(
                            color:
                                palette.textPrimary.withValues(alpha: 0.85)),
                      ),
                      if (caption.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              for (var i = 0; i < caption.length; i++) ...[
                                if (i > 0)
                                  Text(' · ',
                                      style: AppTypography.caption.copyWith(
                                          color: palette.textMuted)),
                                caption[i],
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (canPrint)
                  // A flagged entry's label waits for the sign-off: the
                  // button is faded and says so on tap.
                  Opacity(
                    opacity: a.needsSignoff ? 0.35 : 1,
                    child: IconButton(
                      key: ValueKey('analysis-print-${a.id}'),
                      tooltip: 'Print label',
                      icon: const Icon(Icons.print_outlined),
                      onPressed: a.needsSignoff
                          ? () => _refuseUnsigned(a)
                          : _reprinting.contains(a.id)
                              ? null
                              : () => _reprint(a),
                    ),
                  )
                else
                  const SizedBox(width: Spacing.md),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small outlined tag on an entry: "DIL" or "BO" for its role, "Needs
/// sign-off" on one that is not signed off.
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
