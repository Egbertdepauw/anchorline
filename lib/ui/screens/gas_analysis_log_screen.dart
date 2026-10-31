/// Cylinder analysis log (issue #111): saved gas-analyzer readings,
/// newest first, optionally narrowed to one cylinder. Swipe to delete
/// (soft delete, synced). The app-bar action exports the shown entries
/// as CSV through the system share sheet.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/db/gas_analyses_dao.dart';
import '../../data/models/gas_analysis_csv.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';

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
  });

  final GasAnalysesDaoLike dao;

  /// When set, only this cylinder's analyses are listed.
  final String? cylinderId;

  /// Shown in the title when [cylinderId] is set.
  final String? cylinderLabel;

  final CsvSharer shareCsv;

  @override
  State<GasAnalysisLogScreen> createState() => _GasAnalysisLogScreenState();
}

class _GasAnalysisLogScreenState extends State<GasAnalysisLogScreen> {
  static final _dateFormat = DateFormat('d MMM yyyy, HH:mm');

  List<GasAnalysis>? _items;
  StreamSubscription<void>? _changes;

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

  Future<void> _reload() async {
    final items = await widget.dao.list(cylinderId: widget.cylinderId);
    if (!mounted) return;
    setState(() => _items = items);
  }

  Future<void> _delete(GasAnalysis a) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _items = [...?_items]..removeWhere((x) => x.id == a.id));
    await widget.dao.softDelete(a.id);
    messenger.showSnackBar(
      SnackBar(content: Text('Deleted ${a.mixName} analysis.')),
    );
    await _reload();
  }

  Future<void> _export() async {
    final items = _items;
    if (items == null || items.isEmpty) return;
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
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => Divider(
                      height: 1, color: context.palette.surfaceRaised),
                  itemBuilder: (context, i) => _tile(context, items[i]),
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
        subtitle: Text(
          details.join(' · '),
          style: AppTypography.body.copyWith(color: palette.textSecondary),
        ),
        trailing: a.notes == null
            ? null
            : Tooltip(
                message: a.notes!,
                child: Icon(Icons.notes, color: palette.textMuted),
              ),
      ),
    );
  }
}
