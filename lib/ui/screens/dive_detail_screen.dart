import 'dart:convert';
import 'package:flutter/material.dart';
import '../../data/db/database.dart';
import '../../data/db/dive_annotations_dao.dart';
import '../../data/db/dive_dao.dart';
import '../../data/db/equipment_dao.dart';
import '../../data/models/dive.dart' show DiveGasMix;
import '../../data/sample_codec/active_per_mix.dart';
import '../../data/sample_codec/dive_stats.dart';
import '../../shearwater/parser/hardware.dart';
import '../notifiers/dive_annotations_notifier.dart';
import '../notifiers/dive_detail_notifier.dart';
import '../util/dive_mode_color.dart';
import '../util/format.dart';
import '../widgets/crosshair_overlay.dart';
import '../widgets/crosshair_tooltip.dart';
import '../widgets/dive_annotations_section.dart';
import '../widgets/profile_chart.dart';
import '../widgets/star_rating.dart';
import '../widgets/trace_toggle.dart';

class DiveDetailScreen extends StatefulWidget {
  final Dive dive;
  final DiveDao dao;
  final DiveAnnotationsDao annotationsDao;
  final EquipmentDao equipmentDao;
  const DiveDetailScreen({
    super.key,
    required this.dive,
    required this.dao,
    required this.annotationsDao,
    required this.equipmentDao,
  });
  @override
  State<DiveDetailScreen> createState() => _DiveDetailScreenState();
}

class _DiveDetailScreenState extends State<DiveDetailScreen> {
  late final DiveDetailNotifier _notifier;
  late final DiveAnnotationsNotifier _annotationsNotifier;

  @override
  void initState() {
    super.initState();
    _notifier = DiveDetailNotifier(
      dive: widget.dive,
      dao: widget.dao,
      equipmentDao: widget.equipmentDao,
    );
    _notifier.addListener(_onChanged);
    _notifier.loadSamples();

    _annotationsNotifier = DiveAnnotationsNotifier(widget.annotationsDao);
    _annotationsNotifier.addListener(_onChanged);
    _annotationsNotifier.load(widget.dive.id);
  }

  @override
  void dispose() {
    _notifier.removeListener(_onChanged);
    _notifier.dispose();
    _annotationsNotifier.removeListener(_onChanged);
    _annotationsNotifier.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final dive = widget.dive;
    final modeColor = diveModeColor(dive.diveMode);
    final theme = Theme.of(context);
    final modelName = dive.dcModel < ShearwaterModel.values.length
        ? ShearwaterModel.values[dive.dcModel].name
        : 'Unknown';

    return PopScope(
      canPop: !_annotationsNotifier.dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldDiscard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Unsaved changes'),
            content: const Text(
                'You have unsaved annotation edits. Discard them and leave?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        if (shouldDiscard == true && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text('Dive #${dive.dcDiveNumber}'),
        actions: [
          AnimatedBuilder(
            animation: _annotationsNotifier,
            builder: (context, _) {
              final dirty = _annotationsNotifier.dirty;
              return IconButton(
                tooltip: dirty ? 'Save (unsaved changes)' : 'Save',
                icon: Icon(
                  dirty ? Icons.save : Icons.save_outlined,
                  color: dirty
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                onPressed: dirty
                    ? () async {
                        await _annotationsNotifier.save();
                      }
                    : null,
              );
            },
          ),
        ],
      ),
      body: _notifier.loading && _notifier.samples == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Builder(builder: (context) {
                    final siteName = _annotationsNotifier.siteName;
                    final hasSite =
                        siteName != null && siteName.isNotEmpty;
                    return Container(
                      color: const Color(0xFF152238),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Row(children: [
                                    Text(diveModeLabel(dive.diveMode),
                                        style: TextStyle(
                                            color: modeColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(width: 6),
                                    Text('#${dive.dcDiveNumber}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16)),
                                    const SizedBox(width: 8),
                                    Text(modelName,
                                        style: TextStyle(
                                            color: theme
                                                .colorScheme.onSurface
                                                .withValues(alpha: 0.4),
                                            fontSize: 12)),
                                  ]),
                                  const SizedBox(height: 4),
                                  Text(formatDateTime(dive.startTime),
                                      style: TextStyle(
                                          color: theme
                                              .colorScheme.onSurface
                                              .withValues(alpha: 0.5),
                                          fontSize: 12)),
                                  if (hasSite) ...[
                                    const SizedBox(height: 2),
                                    Text(siteName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: theme
                                                .colorScheme.onSurface
                                                .withValues(alpha: 0.7),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500)),
                                  ],
                                  if (_annotationsNotifier
                                      .buddies.isNotEmpty)
                                    Text(
                                      _annotationsNotifier.buddies.join(', '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.5),
                                          fontSize: 11),
                                    ),
                                ])),
                            Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(formatDepth(dive.maxDepthMm),
                                      style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w600,
                                          color: modeColor)),
                                  Text(
                                      '${formatDuration(dive.durationSeconds)} ${formatGf(dive.gfLow, dive.gfHigh)}',
                                      style: TextStyle(
                                          color: theme
                                              .colorScheme.onSurface
                                              .withValues(alpha: 0.5),
                                          fontSize: 11)),
                                  StarRating(
                                    value: _annotationsNotifier.rating,
                                    onChanged: (v) =>
                                        _annotationsNotifier.setRating(v),
                                  ),
                                ]),
                          ]),
                    );
                  }),

                  // Profile chart
                  if (_notifier.samples != null) ...[
                    SizedBox(
                        height: 250,
                        child: LayoutBuilder(builder: (context, constraints) {
                          return CrosshairOverlay(
                            sampleCount: _notifier.samples!.sampleCount,
                            chartLeftPad: 40,
                            chartRightPad: 44,
                            onIndexChanged: _notifier.setCrosshairIndex,
                            onRelease: _notifier.clearCrosshair,
                            child: Stack(children: [
                              ProfileChart(
                                  samples: _notifier.samples!,
                                  visibleTraces: _notifier.visibleTraces,
                                  crosshairIndex: _notifier.crosshairIndex,
                                  cellsBySlot: _notifier.activeCells),
                              if (_notifier.crosshairIndex != null)
                                CrosshairTooltip(
                                  samples: _notifier.samples!,
                                  sampleIndex: _notifier.crosshairIndex!,
                                  visibleTraces: _notifier.visibleTraces,
                                  chartX: 40 +
                                      (_notifier.crosshairIndex! /
                                              (_notifier.samples!
                                                      .sampleCount -
                                                  1)) *
                                          (constraints.maxWidth - 84),
                                  chartWidth: constraints.maxWidth,
                                  cellsBySlot: _notifier.activeCells,
                                ),
                            ]),
                          );
                        })),
                    TraceToggleChips(
                        visibleTraces: _notifier.visibleTraces,
                        onToggle: _notifier.toggleTrace),
                    _buildStatsRow(theme),
                    _buildAnnotationsSection(),
                  ],
                ],
              )),
      ),
    );
  }

  Widget _buildAnnotationsSection() {
    final samples = _notifier.samples;
    if (samples == null) return const SizedBox.shrink();

    final gasMixes = _decodeGasMixes();
    final activeByMix = activeSecondsPerMix(
      gasMixIndexes: samples.gasMixIndex,
      sampleCount: samples.sampleCount,
      sampleIntervalMs: samples.sampleIntervalMs,
    );

    return DiveAnnotationsSection(
      notifier: _annotationsNotifier,
      gasMixes: gasMixes,
      activeSecondsByMix: activeByMix,
      annotationsDao: widget.annotationsDao,
      equipmentDao: widget.equipmentDao,
    );
  }

  /// Decode gas mixes from the dive's JSON column.
  List<DiveGasMix> _decodeGasMixes() {
    return (jsonDecode(widget.dive.gasMixesJson) as List)
        .map((e) => DiveGasMix.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Choose the diluent label for the GAS column. Picks the diluent with
  /// the most active time; tie-breaker is list order. Returns '—' if the
  /// dive has no diluent (OC dives).
  String _activeDiluentLabel(
      List<DiveGasMix> mixes, Map<int, int> activeSecondsByMix) {
    final diluentEntries = <MapEntry<int, DiveGasMix>>[];
    for (var i = 0; i < mixes.length; i++) {
      if (mixes[i].isDiluent) diluentEntries.add(MapEntry(i, mixes[i]));
    }
    if (diluentEntries.isEmpty) return '—';
    diluentEntries.sort((a, b) {
      final aSec = activeSecondsByMix[a.key] ?? 0;
      final bSec = activeSecondsByMix[b.key] ?? 0;
      return bSec.compareTo(aSec);
    });
    final winner = diluentEntries.first.value;
    return '${winner.oxygenPercent}/${winner.heliumPercent}';
  }

  Widget _buildStatsRow(ThemeData theme) {
    final samples = _notifier.samples!;
    final n = samples.sampleCount;
    final ppo2Stats = minAvgMax(samples.ppo2Bar, n);
    final tempStats = minAvgMax(samples.temperatureCelsius, n);
    var maxCns = 0.0;
    for (var i = 0; i < n; i++) {
      if (samples.cns[i] > maxCns) maxCns = samples.cns[i];
    }
    final gasMixes = _decodeGasMixes();
    final activeByMix = activeSecondsPerMix(
      gasMixIndexes: samples.gasMixIndex,
      sampleCount: samples.sampleCount,
      sampleIntervalMs: samples.sampleIntervalMs,
    );
    final gasLabel = _activeDiluentLabel(gasMixes, activeByMix);

    final otu = computeOtu(
      ppo2Bar: samples.ppo2Bar,
      sampleCount: samples.sampleCount,
      sampleIntervalMs: samples.sampleIntervalMs,
    );
    final showOtu = otu > 0;

    final vSpeed = verticalSpeedExtremes(
      depthMeters: samples.depthMeters,
      sampleCount: samples.sampleCount,
      sampleIntervalMs: samples.sampleIntervalMs,
    );

    final dive = widget.dive;
    final stackEnd = dive.stackRemainingAtEndSeconds;
    final stackStart = dive.stackRemainingAtStartSeconds;
    final stackCfg = dive.configuredStackSeconds;
    final stackLabel = stackEnd == null ? '—' : formatStackHm(stackEnd);
    final stackUsed = (stackEnd != null && stackStart != null)
        ? formatStackUsedMs(stackStart - stackEnd)
        : null;
    final stackConf = stackCfg != null ? formatStackHm(stackCfg) : null;

    return LayoutBuilder(builder: (context, constraints) {
      final cells = <Widget>[
        if (ppo2Stats != null)
          _avgMinMaxCell(
              'PPO2 (bar)',
              ppo2Stats.avg.toStringAsFixed(2),
              ppo2Stats.min.toStringAsFixed(2),
              ppo2Stats.max.toStringAsFixed(2),
              theme)
        else
          _statCell('PPO2', '—', theme),
        _statCell('CNS', '${(maxCns * 100).toInt()}%', theme),
        if (showOtu) _statCell('OTU', '${otu.round()}', theme),
        if (tempStats != null)
          _avgMinMaxCell(
              'TEMP',
              '${tempStats.avg.round()}',
              '${tempStats.min.round()}',
              '${tempStats.max.round()}',
              theme,
              unit: '°C')
        else
          _statCell('TEMP', '—', theme),
        _descAscCell(vSpeed.maxDescentMpm.round(),
            vSpeed.maxAscentMpm.round(), theme),
        _statCell('GAS', gasLabel, theme),
        if (stackEnd != null)
          _stackCell(stackLabel, stackUsed, stackConf, theme),
      ];
      // Width per cell at ~95px keeps even the long "PPO2 min/avg/max" label
      // legible. Below that, wrap to a second line.
      const minCellWidth = 95.0;
      final cellWidth =
          (constraints.maxWidth - 16) / cells.length; // 16 = horizontal padding
      final useWrap = cellWidth < minCellWidth;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: useWrap
            ? Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in cells)
                    SizedBox(width: minCellWidth, child: c),
                ],
              )
            : Row(children: [
                for (final c in cells) Expanded(child: c),
              ]),
      );
    });
  }

  // Cell builders return the unexpanded widget. The caller wraps with
  // Expanded inside a Row, or uses raw inside a Wrap (Expanded only works
  // inside Flex parents).

  Widget _statCell(String label, String value, ThemeData theme,
      {String? tooltip}) {
    final cell = Column(children: [
      Text(value,
          style:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      const SizedBox(height: 2),
      Text(label,
          style: TextStyle(
              fontSize: 9,
              color:
                  theme.colorScheme.onSurface.withValues(alpha: 0.4))),
    ]);
    return tooltip == null ? cell : Tooltip(message: tooltip, child: cell);
  }

  Widget _stackCell(
      String value, String? used, String? configured, ThemeData theme) {
    const valueStyle =
        TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
    final faded = TextStyle(
        fontSize: 9,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.4));
    return Column(children: [
      Text('⏱ $value', style: valueStyle),
      if (configured != null) Text('∑ $configured', style: valueStyle),
      if (used != null) Text('▽ $used', style: valueStyle),
      const SizedBox(height: 2),
      Text('STACK', style: faded),
    ]);
  }

  Widget _avgMinMaxCell(
      String label, String avg, String min, String max, ThemeData theme,
      {String unit = ''}) {
    const valueStyle =
        TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
    final faded = TextStyle(
        fontSize: 9,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.4));
    return Column(children: [
      Text('⌀ $avg$unit', style: valueStyle),
      Text('↓ $min$unit', style: valueStyle),
      Text('↑ $max$unit', style: valueStyle),
      const SizedBox(height: 2),
      Text(label, style: faded),
    ]);
  }

  Widget _descAscCell(int desc, int asc, ThemeData theme) {
    const value =
        TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
    final faded = TextStyle(
        fontSize: 9,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.4));
    return Column(children: [
      Text('↓ $desc', style: value),
      Text('↑ $asc', style: value),
      const SizedBox(height: 2),
      Text('MAX m/min', style: faded),
    ]);
  }
}
