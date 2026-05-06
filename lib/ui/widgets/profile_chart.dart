/// Multi-trace dive profile chart.
///
/// Renders depth, PPO2, setpoint, deco ceiling, O2 cells, and an
/// optional crosshair scrubber on a [CustomPaint] canvas.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../../data/models/sample_set.dart';
import '../notifiers/dive_detail_notifier.dart';

// ── Layout constants ────────────────────────────────────────────

const double _leftPad = 40.0;
const double _rightPad = 44.0;
const double _topPad = 8.0;
const double _bottomPad = 24.0;

// ── Trace colours ───────────────────────────────────────────────

const Color _depthColor = Color(0xFF4FC3F7);
const Color _ppo2Color = Color(0xFF66BB6A);
const Color _setpointColor = Color(0xFFFF9800);
const Color _decoColor = Color(0xFFFF9800);
const Color _cell0Color = Color(0xFFEF5350);
const Color _cell1Color = Color(0xFFFFEE58);
const Color _cell2Color = Color(0xFF42A5F5);
const Color _crosshairColor = Color(0x80FFFFFF);
const Color _gridColor = Color(0xFF1A2A40);
const Color _vSpeedExtremeColor = Colors.redAccent;
const int _vSpeedExtremeHalfWindow = 3;

const double _ppo2Max = 2.0;

/// Petrel default per-cell calibration factor when none is available.
/// Multiplying raw mV by this value yields PPO2 in bar.
const double _defaultCellCal = 0.021;

// ── Widget ──────────────────────────────────────────────────────

/// A [StatelessWidget] that renders a multi-trace dive profile chart.
class ProfileChart extends StatelessWidget {
  final SampleSet samples;
  final Set<TraceType> visibleTraces;
  final int? crosshairIndex;

  /// Per-cell calibration factors (length 3 expected). Used to convert
  /// raw mV to PPO2 (bar) for the cell traces. Falls back to a Petrel
  /// default when null/empty or any factor is non-positive.
  final List<double>? cellCalibration;

  /// Slot-keyed (1-indexed) map of physical cells active at the dive's
  /// start time. Used by [_legend] to label the cell traces.
  final Map<int, OxygenCell>? cellsBySlot;

  /// Sample index of the worst descent rate. When non-null, a short
  /// red overlay is drawn on the depth trace around this sample.
  final int? maxDescentEndIndex;

  /// Sample index of the worst ascent rate. When non-null, a short
  /// red overlay is drawn on the depth trace around this sample.
  final int? maxAscentEndIndex;

  const ProfileChart({
    super.key,
    required this.samples,
    required this.visibleTraces,
    required this.crosshairIndex,
    this.cellCalibration,
    this.cellsBySlot,
    this.maxDescentEndIndex,
    this.maxAscentEndIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      CustomPaint(
        painter: ProfileChartPainter(
          samples: samples,
          visibleTraces: visibleTraces,
          crosshairIndex: crosshairIndex,
          cellCalibration: cellCalibration,
          maxDescentEndIndex: maxDescentEndIndex,
          maxAscentEndIndex: maxAscentEndIndex,
        ),
        child: const SizedBox.expand(),
      ),
      if (visibleTraces.contains(TraceType.cells) &&
          (cellsBySlot?.isNotEmpty ?? false))
        Positioned(
          left: _leftPad + 4,
          top: _topPad + 2,
          child: _CellLegend(cellsBySlot: cellsBySlot!),
        ),
    ]);
  }
}

String cellTraceLabelForSlot(Map<int, OxygenCell>? cellsBySlot, int slot) {
  final cell = cellsBySlot?[slot];
  if (cell == null) return '—';
  final lbl = cell.label?.trim();
  if (lbl == null || lbl.isEmpty) return 'Slot $slot';
  return lbl;
}

class _CellLegend extends StatelessWidget {
  final Map<int, OxygenCell> cellsBySlot;
  const _CellLegend({required this.cellsBySlot});

  @override
  Widget build(BuildContext context) {
    const colors = [_cell0Color, _cell1Color, _cell2Color];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xC0152238),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var slot = 1; slot <= 3; slot++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: colors[slot - 1],
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 4),
                Text(
                  cellTraceLabelForSlot(cellsBySlot, slot),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

// ── Painter ─────────────────────────────────────────────────────

/// [CustomPainter] that performs all rendering for [ProfileChart].
///
/// Exposed as public so tests can access [shouldRepaint] directly.
class ProfileChartPainter extends CustomPainter {
  final SampleSet samples;
  final Set<TraceType> visibleTraces;
  final int? crosshairIndex;
  final List<double>? cellCalibration;
  final int? maxDescentEndIndex;
  final int? maxAscentEndIndex;

  const ProfileChartPainter({
    required this.samples,
    required this.visibleTraces,
    required this.crosshairIndex,
    this.cellCalibration,
    this.maxDescentEndIndex,
    this.maxAscentEndIndex,
  });

  // ── shouldRepaint ──────────────────────────────────────────────

  @override
  bool shouldRepaint(ProfileChartPainter old) {
    return old.crosshairIndex != crosshairIndex ||
        !_setEquals(old.visibleTraces, visibleTraces) ||
        old.maxDescentEndIndex != maxDescentEndIndex ||
        old.maxAscentEndIndex != maxAscentEndIndex ||
        !identical(old.samples, samples);
  }

  static bool _setEquals(Set<TraceType> a, Set<TraceType> b) {
    if (a.length != b.length) return false;
    for (final e in a) {
      if (!b.contains(e)) return false;
    }
    return true;
  }

  // ── paint ──────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.sampleCount == 0) return;

    final n = samples.sampleCount;

    // Chart area bounds.
    final chartLeft = _leftPad;
    final chartTop = _topPad;
    final chartRight = size.width - _rightPad;
    final chartBottom = size.height - _bottomPad;
    final chartWidth = chartRight - chartLeft;
    final chartHeight = chartBottom - chartTop;

    if (chartWidth <= 0 || chartHeight <= 0) return;

    final chartRect = Rect.fromLTRB(chartLeft, chartTop, chartRight, chartBottom);

    // ── Depth scale ────────────────────────────────────────────────
    double maxDepth = 0.0;
    for (int i = 0; i < n; i++) {
      if (samples.depthMeters[i] > maxDepth) maxDepth = samples.depthMeters[i];
    }
    // Round up to nearest 5m, minimum 10m.
    final depthMax = math.max(10.0, (maxDepth / 5.0).ceil() * 5.0);

    // Helpers: convert data coordinates to canvas coordinates.
    double xOf(int i) => chartLeft + (i / (n - 1)) * chartWidth;
    double yDepth(double d) => chartTop + (d / depthMax) * chartHeight;
    double yPpo2(double p) => chartBottom - (p / _ppo2Max) * chartHeight;

    // ── Grid lines ─────────────────────────────────────────────────
    final gridPaint = Paint()
      ..color = _gridColor
      ..strokeWidth = 1.0;

    // Depth grid: every 5m (but skip if too many lines on small charts).
    final depthStep = depthMax <= 30 ? 5.0 : depthMax <= 60 ? 10.0 : 20.0;
    var d = depthStep;
    while (d <= depthMax) {
      final y = yDepth(d);
      canvas.drawLine(Offset(chartLeft, y), Offset(chartRight, y), gridPaint);
      d += depthStep;
    }

    // ── Clip traces to chart area ──────────────────────────────────
    canvas.save();
    canvas.clipRect(chartRect);

    // ── Deco ceiling fill ──────────────────────────────────────────
    if (visibleTraces.contains(TraceType.deco)) {
      bool hasAnyDeco = false;
      for (int i = 0; i < n; i++) {
        if (samples.decoStopDepthMeters[i] > 0) {
          hasAnyDeco = true;
          break;
        }
      }
      if (hasAnyDeco) {
        final decoPaint = Paint()
          ..color = _decoColor.withValues(alpha: 0.15)
          ..style = PaintingStyle.fill;

        final decoPath = Path();
        decoPath.moveTo(xOf(0), chartTop);
        for (int i = 0; i < n; i++) {
          final ceiling = samples.decoStopDepthMeters[i];
          decoPath.lineTo(xOf(i), ceiling > 0 ? yDepth(ceiling) : chartTop);
        }
        decoPath.lineTo(xOf(n - 1), chartTop);
        decoPath.close();
        canvas.drawPath(decoPath, decoPaint);
      }
    }

    // ── Depth fill ─────────────────────────────────────────────────
    {
      final fillPaint = Paint()
        ..color = _depthColor.withValues(alpha: 0.10)
        ..style = PaintingStyle.fill;
      final strokePaint = Paint()
        ..color = _depthColor
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final fillPath = Path();
      final strokePath = Path();

      fillPath.moveTo(xOf(0), chartBottom);
      fillPath.lineTo(xOf(0), yDepth(samples.depthMeters[0]));
      strokePath.moveTo(xOf(0), yDepth(samples.depthMeters[0]));

      for (int i = 1; i < n; i++) {
        final y = yDepth(samples.depthMeters[i]);
        fillPath.lineTo(xOf(i), y);
        strokePath.lineTo(xOf(i), y);
      }
      fillPath.lineTo(xOf(n - 1), chartBottom);
      fillPath.close();

      canvas.drawPath(fillPath, fillPaint);
      canvas.drawPath(strokePath, strokePaint);

      // ── Vertical-speed extremes (red sub-segments) ────────────────
      final extremePaint = Paint()
        ..color = _vSpeedExtremeColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final idx in [maxDescentEndIndex, maxAscentEndIndex]) {
        if (idx == null) continue;
        final lo = (idx - _vSpeedExtremeHalfWindow).clamp(0, n - 1);
        final hi = (idx + _vSpeedExtremeHalfWindow).clamp(0, n - 1);
        if (hi <= lo) continue;
        final p = Path()
          ..moveTo(xOf(lo), yDepth(samples.depthMeters[lo]));
        for (int i = lo + 1; i <= hi; i++) {
          p.lineTo(xOf(i), yDepth(samples.depthMeters[i]));
        }
        canvas.drawPath(p, extremePaint);
      }
    }

    // ── PPO2 trace ─────────────────────────────────────────────────
    if (visibleTraces.contains(TraceType.ppo2)) {
      _drawSolidTrace(
        canvas,
        samples.ppo2Bar,
        n,
        xOf,
        yPpo2,
        _ppo2Color,
        1.5,
      );
    }

    // ── Setpoint trace (dashed) ────────────────────────────────────
    if (visibleTraces.contains(TraceType.setpoint)) {
      _drawDashedTrace(
        canvas,
        samples.setpointBar,
        n,
        xOf,
        yPpo2,
        _setpointColor,
        1.0,
      );
    }

    // ── Cell mV traces ─────────────────────────────────────────────
    if (visibleTraces.contains(TraceType.cells)) {
      // Convert raw mV → PPO2 (bar) using per-cell calibration; fall back
      // to a Petrel default when calibration is missing or invalid.
      final cal = cellCalibration;
      double calOf(int idx) {
        if (cal == null || idx >= cal.length) return _defaultCellCal;
        final c = cal[idx];
        return (c > 0) ? c : _defaultCellCal;
      }

      final c0 = calOf(0);
      final c1 = calOf(1);
      final c2 = calOf(2);
      _drawSolidTrace(canvas, samples.cellMv0, n, xOf,
          (mv) => yPpo2(mv * c0), _cell0Color, 1.0);
      _drawSolidTrace(canvas, samples.cellMv1, n, xOf,
          (mv) => yPpo2(mv * c1), _cell1Color, 1.0);
      _drawSolidTrace(canvas, samples.cellMv2, n, xOf,
          (mv) => yPpo2(mv * c2), _cell2Color, 1.0);
    }

    // ── Crosshair ──────────────────────────────────────────────────
    if (crosshairIndex != null) {
      final ci = crosshairIndex!.clamp(0, n - 1);
      final x = xOf(ci);
      final crossPaint = Paint()
        ..color = _crosshairColor
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(x, chartTop), Offset(x, chartBottom), crossPaint);
    }

    canvas.restore();

    // ── Axis labels (outside clip rect) ───────────────────────────
    _drawDepthLabels(canvas, chartLeft, chartTop, chartBottom, depthMax, depthStep);
    _drawPpo2Labels(canvas, chartRight, chartTop, chartBottom);
    _drawTimeLabels(canvas, chartLeft, chartRight, chartBottom, size.height, n, samples.sampleIntervalMs);
  }

  // ── Trace helpers ──────────────────────────────────────────────

  void _drawSolidTrace(
    Canvas canvas,
    Float32List data,
    int n,
    double Function(int) xOf,
    double Function(double) yOf,
    Color color,
    double width,
  ) {
    if (n == 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    path.moveTo(xOf(0), yOf(data[0]));
    for (int i = 1; i < n; i++) {
      path.lineTo(xOf(i), yOf(data[i]));
    }
    canvas.drawPath(path, paint);
  }

  void _drawDashedTrace(
    Canvas canvas,
    Float32List data,
    int n,
    double Function(int) xOf,
    double Function(double) yOf,
    Color color,
    double width,
  ) {
    if (n == 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;

    final fullPath = Path();
    fullPath.moveTo(xOf(0), yOf(data[0]));
    for (int i = 1; i < n; i++) {
      fullPath.lineTo(xOf(i), yOf(data[i]));
    }

    // Materialise as dashes: 6px on, 4px off.
    const dashOn = 6.0;
    const dashOff = 4.0;
    final dashedPath = Path();

    for (final metric in fullPath.computeMetrics()) {
      double distance = 0.0;
      bool drawing = true;
      while (distance < metric.length) {
        final segLen = drawing ? dashOn : dashOff;
        final end = math.min(distance + segLen, metric.length);
        if (drawing) {
          dashedPath.addPath(
            metric.extractPath(distance, end),
            Offset.zero,
          );
        }
        distance = end;
        drawing = !drawing;
      }
    }

    canvas.drawPath(dashedPath, paint);
  }

  // ── Label helpers ──────────────────────────────────────────────

  void _drawDepthLabels(
    Canvas canvas,
    double chartLeft,
    double chartTop,
    double chartBottom,
    double depthMax,
    double depthStep,
  ) {
    final style = const TextStyle(
      color: Color(0xFF90A4AE),
      fontSize: 9,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    final chartHeight = chartBottom - chartTop;

    var d = depthStep;
    while (d <= depthMax) {
      final y = chartTop + (d / depthMax) * chartHeight;
      final span = TextSpan(text: '${d.toInt()}m', style: style);
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(chartLeft - tp.width - 3, y - tp.height / 2));
      d += depthStep;
    }
  }

  void _drawPpo2Labels(
    Canvas canvas,
    double chartRight,
    double chartTop,
    double chartBottom,
  ) {
    if (!visibleTraces.contains(TraceType.ppo2) &&
        !visibleTraces.contains(TraceType.setpoint) &&
        !visibleTraces.contains(TraceType.cells)) {
      return;
    }
    final style = const TextStyle(
      color: Color(0xFF90A4AE),
      fontSize: 9,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    final chartHeight = chartBottom - chartTop;
    for (final ppo2 in [0.5, 1.0, 1.5, 2.0]) {
      final y = chartBottom - (ppo2 / _ppo2Max) * chartHeight;
      final span = TextSpan(text: ppo2.toStringAsFixed(1), style: style);
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(chartRight + 3, y - tp.height / 2));
    }
  }

  void _drawTimeLabels(
    Canvas canvas,
    double chartLeft,
    double chartRight,
    double chartBottom,
    double totalHeight,
    int n,
    int intervalMs,
  ) {
    final style = const TextStyle(
      color: Color(0xFF90A4AE),
      fontSize: 9,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    final totalSeconds = n * (intervalMs / 1000.0);
    final chartWidth = chartRight - chartLeft;

    // Show ~4 time labels.
    const labelCount = 4;
    for (int k = 0; k <= labelCount; k++) {
      final frac = k / labelCount;
      final secs = (totalSeconds * frac).round();
      final mins = secs ~/ 60;
      final x = chartLeft + frac * chartWidth;
      final label = '${mins}m';
      final span = TextSpan(text: label, style: style);
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, chartBottom + 4));
    }
  }
}
