import 'dart:convert';
import 'package:flutter/material.dart';
import '../../data/db/database.dart';
import '../../data/db/dive_dao.dart';
import '../../shearwater/parser/hardware.dart';
import '../notifiers/dive_detail_notifier.dart';
import '../util/dive_mode_color.dart';
import '../util/format.dart';
import '../widgets/crosshair_overlay.dart';
import '../widgets/crosshair_tooltip.dart';
import '../widgets/profile_chart.dart';
import '../widgets/trace_toggle.dart';

class DiveDetailScreen extends StatefulWidget {
  final Dive dive;
  final DiveDao dao;
  const DiveDetailScreen({super.key, required this.dive, required this.dao});
  @override
  State<DiveDetailScreen> createState() => _DiveDetailScreenState();
}

class _DiveDetailScreenState extends State<DiveDetailScreen> {
  late final DiveDetailNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = DiveDetailNotifier(dive: widget.dive, dao: widget.dao);
    _notifier.addListener(_onChanged);
    _notifier.loadSamples();
  }

  @override
  void dispose() {
    _notifier.removeListener(_onChanged);
    _notifier.dispose();
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
      appBar: AppBar(title: Text('Dive #${dive.dcDiveNumber}')),
      body: _notifier.loading && _notifier.samples == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Container(
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
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.4),
                                          fontSize: 12)),
                                ]),
                                const SizedBox(height: 4),
                                Text(formatDateTime(dive.startTime),
                                    style: TextStyle(
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.5),
                                        fontSize: 12)),
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
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.5),
                                        fontSize: 11)),
                              ]),
                        ]),
                  ),

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
                    _buildGasMixes(theme),
                  ],
                ],
              )),
    );
  }

  Widget _buildStatsRow(ThemeData theme) {
    final samples = _notifier.samples!;
    final n = samples.sampleCount;
    var ppo2Sum = 0.0;
    for (var i = 0; i < n; i++) {
      ppo2Sum += samples.ppo2Bar[i];
    }
    final avgPpo2 = n > 0 ? ppo2Sum / n : 0.0;
    var maxCns = 0.0;
    for (var i = 0; i < n; i++) {
      if (samples.cns[i] > maxCns) maxCns = samples.cns[i];
    }
    var minTemp = double.infinity;
    for (var i = 0; i < n; i++) {
      if (samples.temperatureCelsius[i] < minTemp) {
        minTemp = samples.temperatureCelsius[i];
      }
    }
    final gasMixes = _parseGasMixes(widget.dive.gasMixesJson);
    final gasLabel = gasMixes.isNotEmpty
        ? formatGasMix(gasMixes[0]['o2'] as int, gasMixes[0]['he'] as int)
        : '—';

    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(children: [
          _statCell('AVG PPO2', avgPpo2.toStringAsFixed(2), theme),
          _statCell('CNS', '${(maxCns * 100).toInt()}%', theme),
          _statCell(
              'TEMP',
              '${minTemp.isFinite ? minTemp.toStringAsFixed(0) : '—'}°C',
              theme),
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

  Widget _buildGasMixes(ThemeData theme) {
    final gasMixes = _parseGasMixes(widget.dive.gasMixesJson);
    if (gasMixes.isEmpty) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Gas Mixes',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5))),
            const SizedBox(height: 8),
            for (final mix in gasMixes)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (mix['dil'] as bool)
                                ? const Color(0xFF4FC3F7)
                                : const Color(0xFFFF9800))),
                    const SizedBox(width: 8),
                    SizedBox(
                        width: 32,
                        child: Text((mix['dil'] as bool) ? 'DIL' : 'GAS',
                            style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5)))),
                    Text(
                        formatGasMix(
                            mix['o2'] as int, mix['he'] as int),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ])),
          ],
        ));
  }

  static List<Map<String, dynamic>> _parseGasMixes(String json) {
    try {
      return (jsonDecode(json) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }
}
