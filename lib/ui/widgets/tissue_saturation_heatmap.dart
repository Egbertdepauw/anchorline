/// 16-band heatmap visualisation of per-compartment tissue saturation
/// over time. Consumes [DecoReplayResult.tissueLoadsPct] — a list of
/// 16 Float32List series (one per ZHL-16 compartment) where each value
/// is the compartment load as a percentage of its current M-value.
///
/// Y-axis = compartment number (1 = fastest, 16 = slowest), labelled
/// on the left gutter. A continuous colour gradient below names the
/// saturation scale (blue → cyan → green → yellow → orange → red).
///
/// Rendering uses a bilinearly-interpolated vertex mesh (one vertex per
/// compartment × N horizontal samples), so adjacent compartments blend
/// smoothly into each other and the time axis is anti-aliased rather
/// than stepped. Matches Subsurface's heatmap appearance.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../analysis/deco/replay_result.dart';
import '../../analysis/deco/tissue_model.dart';

/// Anchor stops for the continuous saturation gradient. Each pair is
/// `(percent, colour)`; values between stops are linearly interpolated.
/// The ramp is biased so the green→yellow→orange transition lives
/// around the 95–100% M-value warning band where the diver's attention
/// should land.
const List<(double, Color)> _gradientStops = [
  (0.0, Color(0xFF1E3A8A)),   // deep blue
  (40.0, Color(0xFF3B82F6)),  // blue
  (70.0, Color(0xFF06B6D4)),  // cyan
  (85.0, Color(0xFF22C55E)),  // green
  (95.0, Color(0xFFFACC15)),  // yellow
  (100.0, Color(0xFFF97316)), // orange
  (115.0, Color(0xFFDC2626)), // red
];

/// Colour for a saturation value (% of M-value), interpolated across
/// [_gradientStops].
Color tissueSaturationColour(double pct) {
  if (pct <= _gradientStops.first.$1) return _gradientStops.first.$2;
  if (pct >= _gradientStops.last.$1) return _gradientStops.last.$2;
  for (var i = 0; i < _gradientStops.length - 1; i++) {
    final lo = _gradientStops[i];
    final hi = _gradientStops[i + 1];
    if (pct >= lo.$1 && pct <= hi.$1) {
      final t = (pct - lo.$1) / (hi.$1 - lo.$1);
      return Color.lerp(lo.$2, hi.$2, t)!;
    }
  }
  return _gradientStops.last.$2;
}

const double _gutterWidth = 56;
const double _legendHeight = 36;
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

/// Continuous colour bar with tick labels — replaces the old four
/// stepped colour chips. The bar is the same gradient `_HeatmapPainter`
/// renders so the diver can read a saturation value off the image
/// directly.
class _ColourLegend extends StatelessWidget {
  final TextStyle style;
  const _ColourLegend({required this.style});

  @override
  Widget build(BuildContext context) {
    final colors = _gradientStops.map((s) => s.$2).toList();
    final firstPct = _gradientStops.first.$1;
    final lastPct = _gradientStops.last.$1;
    final stops = _gradientStops
        .map((s) => (s.$1 - firstPct) / (lastPct - firstPct))
        .toList();
    return Padding(
      padding: const EdgeInsets.only(left: _gutterWidth, top: 6, right: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 8,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors, stops: stops),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0%', style: style),
              Text('70%', style: style),
              Text('95%', style: style),
              Text('100%', style: style),
              Text('>115%', style: style),
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

  /// Horizontal vertex count. 240 columns gives ~1 vertex per pixel on
  /// a typical phone-width chart and lets the GPU interpolate cleanly
  /// between samples even for short dives.
  static const int _sampleCount = 240;

  /// 16 real compartments + 2 mirror rows (top + bottom) so the mesh
  /// extends to y=0 and y=height instead of stopping at the centre of
  /// the first / last band.
  static const int _compartments = 16;
  static const int _meshRows = _compartments + 2;

  @override
  void paint(Canvas canvas, Size size) {
    final loads = replay.tissueLoadsPct;
    if (loads.isEmpty) return;
    final n = loads[0].length;
    if (n == 0) return;

    final totalVerts = _sampleCount * _meshRows;
    final positions = Float32List(totalVerts * 2);
    final colors = Int32List(totalVerts);

    for (var row = 0; row < _meshRows; row++) {
      final compartment = _compartmentForRow(row);
      final series = loads[compartment];
      final y = _yForRow(row, size.height);
      for (var s = 0; s < _sampleCount; s++) {
        final xRatio = s / (_sampleCount - 1);
        final x = xRatio * size.width;
        final si = (xRatio * (n - 1)).round();
        final v = series[si];
        final clean = v.isNaN ? 0.0 : v;
        final idx = row * _sampleCount + s;
        positions[idx * 2] = x;
        positions[idx * 2 + 1] = y;
        colors[idx] = tissueSaturationColour(clean).toARGB32();
      }
    }

    final indices =
        Uint16List((_meshRows - 1) * (_sampleCount - 1) * 6);
    var ix = 0;
    for (var row = 0; row < _meshRows - 1; row++) {
      for (var s = 0; s < _sampleCount - 1; s++) {
        final tl = row * _sampleCount + s;
        final tr = tl + 1;
        final bl = (row + 1) * _sampleCount + s;
        final br = bl + 1;
        indices[ix++] = tl;
        indices[ix++] = tr;
        indices[ix++] = bl;
        indices[ix++] = tr;
        indices[ix++] = br;
        indices[ix++] = bl;
      }
    }

    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      colors: colors,
      indices: indices,
    );
    canvas.drawVertices(vertices, ui.BlendMode.srcOver, Paint());
  }

  /// Maps a mesh row to a compartment index. Row 0 mirrors compartment
  /// 0 (so the mesh reaches y=0); the last row mirrors compartment 15.
  /// All real rows in between map 1:1.
  static int _compartmentForRow(int row) {
    if (row == 0) return 0;
    if (row == _meshRows - 1) return _compartments - 1;
    return row - 1;
  }

  /// y-coordinate for a mesh row. Real compartments land at band
  /// centres `(c + 0.5) / 16 * h`; the mirror rows pin the mesh to the
  /// top and bottom edges of the canvas so the gradient covers the
  /// full height without unpainted bars.
  static double _yForRow(int row, double height) {
    if (row == 0) return 0;
    if (row == _meshRows - 1) return height;
    final c = row - 1;
    return (c + 0.5) / _compartments * height;
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) => !identical(old.replay, replay);
}
