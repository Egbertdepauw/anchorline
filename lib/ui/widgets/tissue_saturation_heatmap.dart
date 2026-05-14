/// 16-band heatmap visualisation of per-compartment tissue saturation
/// over time. Consumes [DecoReplayResult.tissueLoadsPct] — a list of
/// 16 Float32List series (one per ZHL-16 compartment) where each value
/// is the compartment load as a percentage of its current M-value.
///
/// Y-axis = compartment number (1 = fastest, 16 = slowest), labelled
/// on the left gutter. A colour legend below names each saturation band.
library;

import 'package:flutter/material.dart';

import '../../analysis/deco/replay_result.dart';
import '../../analysis/deco/tissue_model.dart';

/// Colour for a saturation value (% of M-value).
Color tissueSaturationColour(double pct) {
  if (pct > 100) return const Color(0xFFDC2626); // red
  if (pct >= 95) return const Color(0xFFF97316); // orange
  if (pct >= 70) return const Color(0xFFFACC15); // yellow
  return const Color(0xFF3B82F6); // blue
}

const double _gutterWidth = 56;
const double _legendHeight = 28;
const double _timeAxisHeight = 14;

class TissueSaturationHeatmap extends StatelessWidget {
  final DecoReplayResult replay;
  final Duration? totalDuration;
  final double height;

  const TissueSaturationHeatmap({
    super.key,
    required this.replay,
    this.totalDuration,
    this.height = 256,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      fontSize: 10,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: _gutterWidth,
                  child: _CompartmentLabels(style: labelStyle),
                ),
                Expanded(
                  child: CustomPaint(
                    painter: _HeatmapPainter(replay: replay),
                    size: Size.infinite,
                  ),
                ),
              ],
            ),
          ),
          if (totalDuration != null)
            SizedBox(
              height: _timeAxisHeight,
              child: Padding(
                padding: const EdgeInsets.only(left: _gutterWidth),
                child: _TimeAxis(total: totalDuration!, style: labelStyle),
              ),
            ),
          SizedBox(
            height: _legendHeight,
            child: _ColourLegend(style: labelStyle),
          ),
        ],
      ),
    );
  }
}

class _TimeAxis extends StatelessWidget {
  final Duration total;
  final TextStyle style;
  const _TimeAxis({required this.total, required this.style});

  @override
  Widget build(BuildContext context) {
    const ticks = 5;
    String fmt(int seconds) {
      final m = seconds ~/ 60;
      if (m < 60) return '${m}m';
      final h = m ~/ 60;
      final mm = m % 60;
      return mm == 0 ? '${h}h' : '${h}h${mm}m';
    }

    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth;
      return Stack(
        children: [
          for (var i = 0; i < ticks; i++)
            Positioned(
              left: i * (w / (ticks - 1)) - 16,
              width: 32,
              top: 0,
              bottom: 0,
              child: Align(
                alignment: i == 0
                    ? Alignment.centerLeft
                    : i == ticks - 1
                        ? Alignment.centerRight
                        : Alignment.center,
                child: Text(
                  fmt(total.inSeconds * i ~/ (ticks - 1)),
                  style: style,
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _CompartmentLabels extends StatelessWidget {
  final TextStyle style;
  const _CompartmentLabels({required this.style});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final bandHeight = c.maxHeight / 16;
      return Stack(
        children: [
          for (var i = 0; i < 16; i++)
            Positioned(
              left: 0,
              right: 4,
              top: i * bandHeight,
              height: bandHeight,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${i + 1}: ${zhl16cTissues[i].halfTimeN2Min.toStringAsFixed(0)}′',
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _ColourLegend extends StatelessWidget {
  final TextStyle style;
  const _ColourLegend({required this.style});

  static const _bands = [
    ('< 70%', Color(0xFF3B82F6)),
    ('70–95%', Color(0xFFFACC15)),
    ('95–100%', Color(0xFFF97316)),
    ('> 100%', Color(0xFFDC2626)),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: _gutterWidth, top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final (label, colour) in _bands)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 14,
                  height: 10,
                  decoration: BoxDecoration(
                    color: colour,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Text(label, style: style),
              ],
            ),
        ],
      ),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final DecoReplayResult replay;
  _HeatmapPainter({required this.replay});

  @override
  void paint(Canvas canvas, Size size) {
    final loads = replay.tissueLoadsPct;
    if (loads.isEmpty) return;
    final n = loads[0].length;
    if (n == 0) return;
    final bandHeight = size.height / 16;
    final paint = Paint();
    for (var c = 0; c < 16; c++) {
      final series = loads[c];
      // Sample at pixel resolution so a 4000-sample dive renders smoothly.
      final pixelW = size.width.ceil();
      for (var px = 0; px < pixelW; px++) {
        final i = ((px / size.width) * (n - 1)).round();
        final value = series[i];
        if (value.isNaN) continue;
        paint.color = tissueSaturationColour(value);
        canvas.drawRect(
          Rect.fromLTWH(px.toDouble(), c * bandHeight, 1, bandHeight),
          paint,
        );
      }
    }
    // Light dividers between bands for visual separation.
    final dividerPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;
    for (var c = 1; c < 16; c++) {
      final y = c * bandHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), dividerPaint);
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) => !identical(old.replay, replay);
}
