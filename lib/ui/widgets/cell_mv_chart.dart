import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Which mV metric the chart is showing.
enum CellMvMetric { surface, peak }

class CellMvChart extends StatefulWidget {
  final List<({DateTime date, double mv, String diveId})> surfaceSeries;
  final List<({DateTime date, double mv, String diveId})> peakSeries;

  /// Peak-mV baseline (max peak of the first 5 dives, from CellHealth). When
  /// non-null, the peak view draws baseline / 0.85x (Watch) / 0.70x (Replace)
  /// reference lines. Null (fewer than 5 dives) => no reference lines.
  final double? baselinePeakMv;
  final double height;
  final void Function(String diveId)? onDiveTap;

  const CellMvChart({
    super.key,
    required this.surfaceSeries,
    required this.peakSeries,
    this.baselinePeakMv,
    this.height = 220,
    this.onDiveTap,
  });

  @override
  State<CellMvChart> createState() => _CellMvChartState();
}

class _CellMvChartState extends State<CellMvChart> {
  CellMvMetric _metric = CellMvMetric.peak;
  int? _selectedIndex;

  List<({DateTime date, double mv, String diveId})> get _series =>
      _metric == CellMvMetric.peak ? widget.peakSeries : widget.surfaceSeries;

  // Threshold lines apply to the peak view only, and only with a baseline.
  double? get _baseline =>
      _metric == CellMvMetric.peak ? widget.baselinePeakMv : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<CellMvMetric>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                  value: CellMvMetric.surface, label: Text('Surface mV')),
              ButtonSegment(value: CellMvMetric.peak, label: Text('Peak mV')),
            ],
            selected: {_metric},
            onSelectionChanged: (s) => setState(() {
              _metric = s.first;
              _selectedIndex = null;
            }),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: widget.height,
          child: _series.isEmpty
              ? Center(
                  child: Text(_metric == CellMvMetric.peak
                      ? 'No peak-mV data yet'
                      : 'No surface-mV data yet'),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final size =
                        Size(constraints.maxWidth, constraints.maxHeight);
                    return GestureDetector(
                      onTapDown: (details) =>
                          _handleTap(details.localPosition, size),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _ChartPainter(
                                _series,
                                theme,
                                _selectedIndex,
                                _baseline,
                              ),
                            ),
                          ),
                          if (_selectedIndex != null)
                            _Tooltip(
                              point: _series[_selectedIndex!],
                              onTap: widget.onDiveTap == null
                                  ? null
                                  : () => widget.onDiveTap!(
                                      _series[_selectedIndex!].diveId),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _handleTap(Offset tap, Size size) {
    final series = _series;
    final layout = _ChartLayout(size, series, _baseline);
    var bestIndex = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < series.length; i++) {
      final p = layout.pointAt(i);
      final dx = p.dx - tap.dx;
      final dy = p.dy - tap.dy;
      final d = dx * dx + dy * dy;
      if (d < bestDist) {
        bestDist = d;
        bestIndex = i;
      }
    }
    // Only select if the tap is within ~32px of the nearest point.
    if (math.sqrt(bestDist) > 32) {
      setState(() => _selectedIndex = null);
      return;
    }
    setState(() => _selectedIndex = bestIndex);
  }
}

/// Geometry helper shared by the painter and the tap handler. The mV axis is
/// padded to a "nice" rounded range; when a [baseline] is present the range is
/// widened to keep the 0.70x..baseline reference lines visible.
class _ChartLayout {
  final Size size;
  final List<({DateTime date, double mv, String diveId})> series;
  final double? baseline;
  late final double minTime;
  late final double maxTime;
  late final double niceMinMv;
  late final double niceMaxMv;
  late final double mvStep;
  late final double timeRange;
  late final double mvRange;

  static const double left = 46.0;
  static const double right = 14.0;
  static const double top = 14.0;
  static const double bottom = 24.0;

  _ChartLayout(this.size, this.series, this.baseline) {
    minTime = series.first.date.millisecondsSinceEpoch.toDouble();
    maxTime = series.last.date.millisecondsSinceEpoch.toDouble();
    final mvs = series.map((p) => p.mv);
    var lo = mvs.reduce(math.min);
    var hi = mvs.reduce(math.max);
    final b = baseline;
    if (b != null && b > 0) {
      lo = math.min(lo, b * 0.70);
      hi = math.max(hi, b);
    }
    final (nMin, nMax, step) = _niceRange(lo, hi);
    niceMinMv = nMin;
    niceMaxMv = nMax;
    mvStep = step;
    timeRange = (maxTime - minTime).clamp(1, double.infinity).toDouble();
    mvRange = (niceMaxMv - niceMinMv).clamp(1.0, double.infinity);
  }

  double get plotW => (size.width - left - right).clamp(1.0, double.infinity);
  double get plotH => (size.height - top - bottom).clamp(1.0, double.infinity);

  double xAt(double timeMillis) =>
      left + ((timeMillis - minTime) / timeRange) * plotW;
  double yAt(double mv) => top + plotH - ((mv - niceMinMv) / mvRange) * plotH;

  Offset pointAt(int i) => Offset(
      xAt(series[i].date.millisecondsSinceEpoch.toDouble()),
      yAt(series[i].mv));
}

/// Round a [lo]-[hi] span out to nice gridline-friendly bounds, returning
/// `(niceMin, niceMax, step)`. A flat span gets a small symmetric band.
(double, double, double) _niceRange(double lo, double hi) {
  if ((hi - lo).abs() < 1e-9) {
    final band = lo.abs() < 1e-9 ? 1.0 : (lo.abs() * 0.1).clamp(0.5, 5.0);
    return (lo - band, lo + band, band);
  }
  final step = _niceStep(hi - lo, 4);
  final niceMin = (lo / step).floorToDouble() * step;
  final niceMax = (hi / step).ceilToDouble() * step;
  return (niceMin, niceMax, step);
}

double _niceStep(double range, int targetTicks) {
  final raw = range / targetTicks;
  if (raw <= 0) return 1;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
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

const _monthAbbr = [
  '',
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatMonthYear(DateTime d) {
  final local = d.toLocal();
  return "${_monthAbbr[local.month]} '${(local.year % 100).toString().padLeft(2, '0')}";
}

class _ChartPainter extends CustomPainter {
  final List<({DateTime date, double mv, String diveId})> series;
  final ThemeData theme;
  final int? selectedIndex;
  final double? baseline;

  _ChartPainter(this.series, this.theme, this.selectedIndex, this.baseline);

  static const _gridColor = Color(0xFF1A2832); // AppColors.wreck.chartGrid
  static const _axisLabel = Color(0xFFA0AEB6); // AppColors.wreck.textSecondary
  static const _watchColor = Color(0xFFF39C12); // AppColors.wreck.statusWarning
  static const _replaceColor = Color(0xFFE74C3C); // AppColors.wreck.statusDanger

  static const _labelStyle = TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: 9,
    color: _axisLabel,
    height: 1.0,
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    final layout = _ChartLayout(size, series, baseline);

    final gridPaint = Paint()
      ..color = _gridColor
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = theme.colorScheme.outline
      ..strokeWidth = 1;

    // mV grid + labels
    final decimals = layout.mvStep >= 1 ? 0 : 1;
    for (var v = layout.niceMinMv;
        v <= layout.niceMaxMv + 1e-6;
        v += layout.mvStep) {
      final y = layout.yAt(v);
      canvas.drawLine(
        Offset(_ChartLayout.left, y),
        Offset(_ChartLayout.left + layout.plotW, y),
        gridPaint,
      );
      final tp = TextPainter(
        text: TextSpan(text: v.toStringAsFixed(decimals), style: _labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          Offset(_ChartLayout.left - tp.width - 5, y - tp.height / 2));
    }

    // "mV" unit above the top of the axis.
    final unitTp = TextPainter(
      text: const TextSpan(
        text: 'mV',
        style: TextStyle(fontFamily: 'Inter', fontSize: 9, color: _axisLabel),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    unitTp.paint(canvas,
        Offset(_ChartLayout.left - unitTp.width - 5, _ChartLayout.top - 12));

    // Date axis (4 ticks evenly across the time span)
    const dateTicks = 3; // 4 labels: i = 0..3
    for (var i = 0; i <= dateTicks; i++) {
      final frac = i / dateTicks;
      final t = layout.minTime + frac * layout.timeRange;
      final x = layout.xAt(t);
      final tp = TextPainter(
        text: TextSpan(
          text: _formatMonthYear(
              DateTime.fromMillisecondsSinceEpoch(t.round())),
          style: _labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      double lx;
      if (i == 0) {
        lx = x;
      } else if (i == dateTicks) {
        lx = x - tp.width;
      } else {
        lx = x - tp.width / 2;
      }
      tp.paint(canvas, Offset(lx, _ChartLayout.top + layout.plotH + 6));
    }

    // Threshold reference lines (peak view with a baseline)
    final b = baseline;
    if (b != null && b > 0) {
      _drawThreshold(canvas, layout, b, _axisLabel, 'base', dashed: false);
      _drawThreshold(canvas, layout, b * 0.85, _watchColor, '0.85x',
          dashed: true);
      _drawThreshold(canvas, layout, b * 0.70, _replaceColor, '0.70x',
          dashed: true);
    }

    // Axes
    canvas.drawLine(
      const Offset(_ChartLayout.left, _ChartLayout.top),
      Offset(_ChartLayout.left, _ChartLayout.top + layout.plotH),
      axisPaint,
    );
    canvas.drawLine(
      Offset(_ChartLayout.left, _ChartLayout.top + layout.plotH),
      Offset(_ChartLayout.left + layout.plotW,
          _ChartLayout.top + layout.plotH),
      axisPaint,
    );

    // Trend line + dots
    final linePaint = Paint()
      ..color = theme.colorScheme.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    final dotPaint = Paint()..color = theme.colorScheme.primary;
    final selectedPaint = Paint()..color = theme.colorScheme.error;

    final path = Path()
      ..moveTo(layout.pointAt(0).dx, layout.pointAt(0).dy);
    for (var i = 1; i < series.length; i++) {
      final p = layout.pointAt(i);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, linePaint);

    for (var i = 0; i < series.length; i++) {
      final p = layout.pointAt(i);
      final isSelected = i == selectedIndex;
      canvas.drawCircle(
        p,
        isSelected ? 5 : 3,
        isSelected ? selectedPaint : dotPaint,
      );
    }
  }

  void _drawThreshold(
    Canvas canvas,
    _ChartLayout layout,
    double mv,
    Color color,
    String label, {
    required bool dashed,
  }) {
    if (mv < layout.niceMinMv || mv > layout.niceMaxMv) return;
    final y = layout.yAt(mv);
    final x0 = _ChartLayout.left;
    final x1 = _ChartLayout.left + layout.plotW;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    if (dashed) {
      _drawDashedLine(canvas, Offset(x0, y), Offset(x1, y), paint,
          dashWidth: 4, gapWidth: 3);
    } else {
      canvas.drawLine(Offset(x0, y), Offset(x1, y), paint);
    }
    final tp = TextPainter(
      text: TextSpan(text: label, style: _labelStyle.copyWith(color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x1 - tp.width - 2, y - tp.height - 1));
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
      final next = Offset(cursor.dx + ux * step, cursor.dy + uy * step);
      if (drawing) canvas.drawLine(cursor, next, paint);
      cursor = next;
      travelled += step;
      drawing = !drawing;
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.series != series ||
      old.theme != theme ||
      old.selectedIndex != selectedIndex ||
      old.baseline != baseline;
}

class _Tooltip extends StatelessWidget {
  final ({DateTime date, double mv, String diveId}) point;
  final VoidCallback? onTap;

  const _Tooltip({required this.point, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr = point.date.toLocal().toString().split(' ').first;
    return Positioned(
      top: 8,
      right: 8,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(6),
        color: theme.colorScheme.surface,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateStr, style: theme.textTheme.labelMedium),
                Text('${point.mv.toStringAsFixed(1)} mV',
                    style: theme.textTheme.titleMedium),
                if (onTap != null)
                  Text('Open dive →',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
