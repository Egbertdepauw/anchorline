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
    _notifier = DiveDetailNotifier(dive: widget.dive, dao: widget.dao);
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

    return Scaffold(
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
                                  crosshairIndex: _notifier.crosshairIndex),
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

    final ppo2Label = ppo2Stats == null
        ? '—'
        : '${ppo2Stats.min.toStringAsFixed(2)} / ${ppo2Stats.avg.toStringAsFixed(2)} / ${ppo2Stats.max.toStringAsFixed(2)}';

    final tempLabel = tempStats == null
        ? '—'
        : '${tempStats.min.round()}/${tempStats.avg.round()}/${tempStats.max.round()}°C';

    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(children: [
          _statCell('PPO2 min/avg/max', ppo2Label, theme),
          _statCell('CNS', '${(maxCns * 100).toInt()}%', theme),
          if (showOtu) _statCell('OTU', '${otu.round()}', theme),
          _statCell('TEMP min/avg/max', tempLabel, theme),
          _statCell('GAS', gasLabel, theme),
        ]));
  }

  Widget _statCell(String label, String value, ThemeData theme) {
    return Expanded(
        child: Column(children: [
      Text(value,
          style:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      const SizedBox(height: 2),
      Text(label,
          style: TextStyle(
              fontSize: 9,
              color:
                  theme.colorScheme.onSurface.withValues(alpha: 0.4))),
    ]));
  }
}
