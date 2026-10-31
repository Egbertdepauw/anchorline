/// Live O2 + He chart for the gas analyzer screen: the last two minutes,
/// so the diver can watch the reading settle.
///
/// Plain CustomPainter, no chart dependency. Colours come from the owning
/// widget (painters have no BuildContext).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../analyzer/analyzer_controller.dart' show AnalyzerHistoryPoint;
import '../theme/tokens.dart';

class AnalyzerLiveChart extends StatelessWidget {
  const AnalyzerLiveChart({
    super.key,
    required this.points,
    required this.nowSeconds,
    required this.o2Color,
    required this.heColor,
    this.windowSeconds = 120,
    this.height = 200,
  });

  final List<AnalyzerHistoryPoint> points;

  /// Time of the right-hand edge ("now"), on the same axis as
  /// [AnalyzerHistoryPoint.seconds].
  final double nowSeconds;
  final Color o2Color;
  final Color heColor;
  final double windowSeconds;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: AnalyzerChartPainter(
          points: points,
          nowSeconds: nowSeconds,
          windowSeconds: windowSeconds,
          o2Color: o2Color,
          heColor: heColor,
          gridColor: palette.chartGrid,
          labelColor: palette.textMuted,
        ),
      ),
    );
  }
}

class AnalyzerChartPainter extends CustomPainter {
  AnalyzerChartPainter({
    required this.points,
    required this.nowSeconds,
    required this.windowSeconds,
    required this.o2Color,
    required this.heColor,
    required this.gridColor,
    required this.labelColor,
  });

  final List<AnalyzerHistoryPoint> points;
  final double nowSeconds;
  final double windowSeconds;
  final Color o2Color;
  final Color heColor;
  final Color gridColor;
  final Color labelColor;

  static const double _padLeft = 34;
  static const double _padRight = 8;
  static const double _padTop = 8;
  static const double _padBottom = 18;

  @override
  void paint(Canvas canvas, Size size) {
    final valid =
        points.where((p) => p.o2.isFinite && p.he.isFinite).toList();

    // Y range: data ± 2 %, clamped to 0–100, at least 5 % tall.
    var lo = 0.0, hi = 100.0;
    if (valid.isNotEmpty) {
      lo = double.infinity;
      hi = double.negativeInfinity;
      for (final p in valid) {
        lo = math.min(lo, math.min(p.o2, p.he));
        hi = math.max(hi, math.max(p.o2, p.he));
      }
      lo = math.max(0, (lo - 2).floorToDouble());
      hi = math.min(100, (hi + 2).ceilToDouble());
      if (hi - lo < 5) hi = lo + 5;
    }

    final plotW = size.width - _padLeft - _padRight;
    final plotH = size.height - _padTop - _padBottom;
    double x(double s) =>
        _padLeft + (1 - (nowSeconds - s) / windowSeconds) * plotW;
    double y(double v) => _padTop + (1 - (v - lo) / (hi - lo)) * plotH;

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final v = lo + (hi - lo) * i / 4;
      final yy = y(v);
      canvas.drawLine(
          Offset(_padLeft, yy), Offset(size.width - _padRight, yy), grid);
      _label(canvas, v.toStringAsFixed(0), Offset(2, yy - 7));
    }
    _label(canvas, '-2 min', Offset(_padLeft, size.height - 14));
    _label(canvas, 'now', Offset(size.width - _padRight - 24,
        size.height - 14));

    if (valid.length < 2) return;
    canvas.save();
    canvas.clipRect(
        Rect.fromLTWH(_padLeft, 0, plotW, size.height));
    _trace(canvas, valid, (p) => p.he, heColor, x, y);
    _trace(canvas, valid, (p) => p.o2, o2Color, x, y);
    canvas.restore();
  }

  void _trace(
    Canvas canvas,
    List<AnalyzerHistoryPoint> pts,
    double Function(AnalyzerHistoryPoint) value,
    Color color,
    double Function(double) x,
    double Function(double) y,
  ) {
    final path = Path()..moveTo(x(pts.first.seconds), y(value(pts.first)));
    for (final p in pts.skip(1)) {
      path.lineTo(x(p.seconds), y(value(p)));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  void _label(Canvas canvas, String text, Offset at) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: AppTypography.readoutSm.copyWith(
            fontSize: 11, color: labelColor),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(AnalyzerChartPainter old) =>
      old.points != points ||
      old.nowSeconds != nowSeconds ||
      old.o2Color != o2Color ||
      old.heColor != heColor ||
      old.gridColor != gridColor ||
      old.labelColor != labelColor;
}
