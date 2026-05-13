/// 16-band heatmap visualisation of per-compartment tissue saturation
/// over time. Consumes [DecoReplayResult.tissueLoadsPct] — a list of
/// 16 Float32List series (one per ZHL-16 compartment) where each value
/// is the compartment load as a percentage of its current M-value.
///
/// X-axis = dive time (sample index). Y-axis = compartment (top = fastest).
library;

import 'package:flutter/material.dart';

import '../../analysis/deco/replay_result.dart';

/// Colour for a saturation value (% of M-value).
Color tissueSaturationColour(double pct) {
  if (pct > 100) return const Color(0xFFDC2626); // red
  if (pct >= 95) return const Color(0xFFF97316); // orange
  if (pct >= 70) return const Color(0xFFFACC15); // yellow
  return const Color(0xFF3B82F6); // blue
}

class TissueSaturationHeatmap extends StatelessWidget {
  final DecoReplayResult replay;
  final double height;

  const TissueSaturationHeatmap({
    super.key,
    required this.replay,
    this.height = 256,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _HeatmapPainter(replay: replay),
        size: Size.infinite,
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
        // Map pixel column to sample index.
        final i = ((px / size.width) * (n - 1)).round();
        final value = series[i];
        if (value.isNaN) continue;
        paint.color = tissueSaturationColour(value);
        // Draw a 1-px-wide vertical strip at this column for this band.
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
