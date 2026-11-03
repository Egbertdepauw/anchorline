/// DiveProfileChart — schematic depth-vs-time graph for a planned dive.
///
/// Inputs are the same [AscentStop] legs the stop-ladder consumes, so the
/// chart and the table always agree on what's being drawn. The plan
/// surface is rendered as a filled polygon (water depth) with the gas
/// breathed per leg colour-keyed and labelled along the ridge. Gas
/// switches drop a vertical tick down to the depth axis so the diver
/// can see at a glance where each switch lands relative to a stop.
///
/// This is deliberately schematic, not pixel-perfect MultiDeco — it
/// reads at-a-glance the same: shape of the dive, where stops live,
/// where the gas changes happen. No interactivity in v1.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../analysis/bailout/ascent_simulator.dart' show AscentStop;
import 'package:subsurface_core/data/models/dive.dart' show DiveGasMix;
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';
import 'stop_ladder_table.dart' show StopLadderTable;

class DiveProfileChart extends StatelessWidget {
  const DiveProfileChart({
    super.key,
    required this.legs,
    this.height = 180,
    this.title,
  });

  /// Ordered legs of the planned dive, surface → surface. Empty legs
  /// (0-duration gas-switch markers) are dropped before drawing.
  final List<AscentStop> legs;

  /// Drawn area height. Width fills the parent.
  final double height;

  /// Optional label rendered above the chart.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final usable = legs.where((l) => l.duration.inSeconds > 0).toList();
    if (usable.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text('No profile to draw yet.',
              style: AppTypography.caption),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(title!, style: AppTypography.label),
          const SizedBox(height: Spacing.xs),
        ],
        SizedBox(
          height: height,
          child: CustomPaint(
            painter: _DiveProfilePainter(
                legs: usable, palette: context.palette),
          ),
        ),
      ],
    );
  }
}

class _DiveProfilePainter extends CustomPainter {
  _DiveProfilePainter({required this.legs, required this.palette});

  final List<AscentStop> legs;

  /// The active theme palette; the painter has no BuildContext, so the
  /// widget passes it in.
  final ThemePalette palette;

  Color get _gridColor => palette.chartGrid;
  Color get _axisLabel => palette.textSecondary;
  Color get _profileLine => palette.chartTraceDepth;
  Color get _profileFill => palette.surfaceRaised.withValues(alpha: 0.2);
  static const _switchMarker = SafetyColors.info;

  @override
  void paint(Canvas canvas, Size size) {
    // ── Build cumulative (time, depth) waypoints ─────────────────────
    // Each leg contributes:
    //   start: (cumulativeTime, depthStart)
    //   end:   (cumulativeTime + duration, depthEnd)
    // Consecutive legs already share their join point (start of leg N
    // = end of leg N-1), so we add the end point of each leg and the
    // start of leg 0 to seed the path.
    final waypoints = <_Waypoint>[];
    var t = 0.0;
    waypoints.add(_Waypoint(
      time: 0,
      depth: legs.first.depthStartMeters,
      gas: legs.first.gas,
    ));
    for (final leg in legs) {
      t += leg.duration.inSeconds / 60.0;
      waypoints.add(_Waypoint(
        time: t,
        depth: leg.depthEndMeters,
        gas: leg.gas,
      ));
    }
    final totalMinutes = t;
    var maxDepth = 0.0;
    for (final w in waypoints) {
      if (w.depth > maxDepth) maxDepth = w.depth;
    }
    if (totalMinutes <= 0 || maxDepth <= 0) return;

    // ── Layout ───────────────────────────────────────────────────────
    const left = 36.0; // depth axis labels
    const right = 8.0;
    const top = 6.0;
    const bottom = 18.0; // time axis labels
    final plotW = size.width - left - right;
    final plotH = size.height - top - bottom;
    if (plotW <= 0 || plotH <= 0) return;

    // Depth axis: 0 at top, maxDepth (rounded up) at bottom.
    final depthMax = _niceCeiling(maxDepth);
    final timeMax = _niceCeiling(totalMinutes);

    double sx(double minutes) => left + (minutes / timeMax) * plotW;
    double sy(double depth) => top + (depth / depthMax) * plotH;

    // ── Grid ─────────────────────────────────────────────────────────
    final gridPaint = Paint()
      ..color = _gridColor
      ..strokeWidth = 1;
    final labelStyle = TextStyle(
      fontFamily: 'JetBrainsMono',
      fontSize: 9,
      color: _axisLabel,
      height: 1.0,
    );

    // Horizontal depth grid: 4 divisions.
    for (var i = 0; i <= 4; i++) {
      final d = depthMax * (i / 4);
      final y = sy(d);
      canvas.drawLine(
        Offset(left, y),
        Offset(left + plotW, y),
        gridPaint,
      );
      final tp = TextPainter(
        text: TextSpan(text: '${d.round()}m', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(left - tp.width - 4, y - tp.height / 2));
    }
    // Vertical time grid: every "nice" minute step.
    final tStep = _niceStep(timeMax, 5);
    for (var m = 0.0; m <= timeMax + 1e-6; m += tStep) {
      final x = sx(m);
      canvas.drawLine(
        Offset(x, top),
        Offset(x, top + plotH),
        gridPaint,
      );
      final tp = TextPainter(
        text: TextSpan(text: '${m.round()}', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, top + plotH + 4));
    }
    // "min" suffix beneath the right edge.
    final unitTp = TextPainter(
      text: TextSpan(
        text: 'min',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 9,
          color: _axisLabel,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    unitTp.paint(canvas,
        Offset(left + plotW - unitTp.width, top + plotH + 4));

    // ── Filled profile ───────────────────────────────────────────────
    final fillPath = Path()..moveTo(sx(0), sy(0));
    for (final w in waypoints) {
      fillPath.lineTo(sx(w.time), sy(w.depth));
    }
    fillPath.lineTo(sx(totalMinutes), sy(0));
    fillPath.close();
    canvas.drawPath(fillPath, Paint()..color = _profileFill);

    // ── Profile line ─────────────────────────────────────────────────
    final linePaint = Paint()
      ..color = _profileLine
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    final linePath = Path()..moveTo(sx(waypoints.first.time), sy(waypoints.first.depth));
    for (var i = 1; i < waypoints.length; i++) {
      linePath.lineTo(sx(waypoints[i].time), sy(waypoints[i].depth));
    }
    canvas.drawPath(linePath, linePaint);

    // ── Gas-switch markers ───────────────────────────────────────────
    // A switch happens at the *start* of a leg whose gas differs from
    // the previous leg. Drop a vertical tick from (time, depth) up
    // toward the surface, plus the new mix label.
    DiveGasMix? prevGas;
    final switchPaint = Paint()
      ..color = _switchMarker
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    var cum = 0.0;
    final labelOffsets = <_Label>[];
    for (final leg in legs) {
      final startTime = cum;
      cum += leg.duration.inSeconds / 60.0;
      if (prevGas != null && leg.gas != prevGas) {
        final x = sx(startTime);
        final y = sy(leg.depthStartMeters);
        canvas.drawLine(Offset(x, y), Offset(x, top), switchPaint);
        labelOffsets.add(_Label(
          x: x,
          y: top + 2,
          text: StopLadderTable.mixLabel(leg.gas),
        ));
      }
      prevGas = leg.gas;
    }
    // Always label the first gas above the start point.
    labelOffsets.insert(
      0,
      _Label(
        x: sx(0) + 4,
        y: top + 2,
        text: StopLadderTable.mixLabel(legs.first.gas),
      ),
    );
    // Render labels with simple collision avoidance — bump labels
    // overlapping the prior one to the right by their measured width.
    double? prevRight;
    for (final lab in labelOffsets) {
      final tp = TextPainter(
        text: TextSpan(
          text: lab.text,
          style: const TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 9,
            color: _switchMarker,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      var x = lab.x + 2;
      final pr = prevRight;
      if (pr != null && x < pr + 4) x = pr + 4;
      tp.paint(canvas, Offset(x, lab.y));
      prevRight = x + tp.width;
    }

    // ── Max-depth pip ────────────────────────────────────────────────
    // Drop a subtle dashed line at maxDepth so the diver eyeballs the
    // floor quickly.
    final maxDepthPaint = Paint()
      ..color = _axisLabel.withValues(alpha: 0.4)
      ..strokeWidth = 0.8;
    _drawDashedLine(
      canvas,
      Offset(left, sy(maxDepth)),
      Offset(left + plotW, sy(maxDepth)),
      maxDepthPaint,
      dashWidth: 4,
      gapWidth: 3,
    );
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint, {
    required double dashWidth,
    required double gapWidth,
  }) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist == 0) return;
    final ux = dx / dist;
    final uy = dy / dist;
    var travelled = 0.0;
    var drawing = true;
    var cursor = a;
    while (travelled < dist) {
      final step = drawing ? dashWidth : gapWidth;
      final next = Offset(
        cursor.dx + ux * step,
        cursor.dy + uy * step,
      );
      if (drawing) canvas.drawLine(cursor, next, paint);
      cursor = next;
      travelled += step;
      drawing = !drawing;
    }
  }

  // Round up to a "nice" axis ceiling so the labels read as round
  // numbers rather than 27 / 31.7 / 84.
  double _niceCeiling(double v) {
    if (v <= 0) return 1;
    final mag = math.pow(10, v.floor().toString().length - 1).toDouble();
    final scaled = v / mag;
    double niceScaled;
    if (scaled <= 1) {
      niceScaled = 1;
    } else if (scaled <= 2) {
      niceScaled = 2;
    } else if (scaled <= 5) {
      niceScaled = 5;
    } else {
      niceScaled = 10;
    }
    return niceScaled * mag;
  }

  double _niceStep(double range, int targetTicks) {
    final raw = range / targetTicks;
    if (raw <= 0) return 1;
    final mag = math.pow(10, raw.floor().toString().length - 1).toDouble();
    final scaled = raw / mag;
    double niceScaled;
    if (scaled < 1.5) {
      niceScaled = 1;
    } else if (scaled < 3) {
      niceScaled = 2;
    } else if (scaled < 7) {
      niceScaled = 5;
    } else {
      niceScaled = 10;
    }
    return niceScaled * mag;
  }

  @override
  bool shouldRepaint(_DiveProfilePainter old) =>
      !_legsEqual(old.legs, legs) || !identical(old.palette, palette);

  bool _legsEqual(List<AscentStop> a, List<AscentStop> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.depthStartMeters != y.depthStartMeters ||
          x.depthEndMeters != y.depthEndMeters ||
          x.duration != y.duration ||
          x.gas != y.gas ||
          x.setpointBar != y.setpointBar) {
        return false;
      }
    }
    return true;
  }
}

class _Waypoint {
  const _Waypoint({
    required this.time,
    required this.depth,
    required this.gas,
  });
  final double time;
  final double depth;
  final DiveGasMix gas;
}

class _Label {
  const _Label({required this.x, required this.y, required this.text});
  final double x;
  final double y;
  final String text;
}
