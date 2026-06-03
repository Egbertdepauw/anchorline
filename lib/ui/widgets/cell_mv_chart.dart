import 'dart:math' as math;

import 'package:flutter/material.dart';

class CellMvChart extends StatefulWidget {
  final List<({DateTime date, double mv, String diveId})> series;
  final double height;
  final void Function(String diveId)? onDiveTap;

  const CellMvChart({
    super.key,
    required this.series,
    this.height = 220,
    this.onDiveTap,
  });

  @override
  State<CellMvChart> createState() => _CellMvChartState();
}

class _CellMvChartState extends State<CellMvChart> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.series.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: const Center(child: Text('No surface-mV data yet')),
      );
    }
    final theme = Theme.of(context);
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            onTapDown: (details) =>
                _handleTap(details.localPosition, size),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ChartPainter(
                      widget.series,
                      theme,
                      _selectedIndex,
                    ),
                  ),
                ),
                if (_selectedIndex != null)
                  _Tooltip(
                    point: widget.series[_selectedIndex!],
                    diveNumberInSeries: _selectedIndex! + 1,
                    onTap: widget.onDiveTap == null
                        ? null
                        : () => widget.onDiveTap!(
                            widget.series[_selectedIndex!].diveId),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _handleTap(Offset tap, Size size) {
    final layout = _chartLayout(size, widget.series);
    var bestIndex = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < widget.series.length; i++) {
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

/// Geometry helper shared by the painter and the tap handler.
///
/// The mV axis is padded to a "nice" rounded range (rather than the raw
/// data min/max) so the gridline labels read as round numbers and the
/// magnitude of the trend is legible at a glance.
class _ChartLayout {
  final Size size;
  final List<({DateTime date, double mv, String diveId})> series;
  late final double minTime;
  late final double maxTime;
  late final double niceMinMv;
  late final double niceMaxMv;
  late final double mvStep;
  late final double timeRange;
  late final double mvRange;

  // Margins: room for the mV labels on the left and the date labels below.
  static const double left = 46.0;
  static const double right = 14.0;
  static const double top = 14.0;
  static const double bottom = 24.0;

  _ChartLayout(this.size, this.series) {
    minTime = series.first.date.millisecondsSinceEpoch.toDouble();
    maxTime = series.last.date.millisecondsSinceEpoch.toDouble();
    final mvs = series.map((p) => p.mv);
    final lo = mvs.reduce(math.min);
    final hi = mvs.reduce(math.max);
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
  double yAt(double mv) =>
      top + plotH - ((mv - niceMinMv) / mvRange) * plotH;

  Offset pointAt(int i) =>
      Offset(xAt(series[i].date.millisecondsSinceEpoch.toDouble()),
          yAt(series[i].mv));
}

_ChartLayout _chartLayout(
  Size size,
  List<({DateTime date, double mv, String diveId})> series,
) =>
    _ChartLayout(size, series);

/// Round a [lo]–[hi] span out to nice gridline-friendly bounds, returning
/// `(niceMin, niceMax, step)`. A flat span gets a small symmetric band so
/// a steady cell still renders a readable axis.
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

  _ChartPainter(this.series, this.theme, this.selectedIndex);

  static const _gridColor = Color(0xFF1A2832); // AppColors.wreck.chartGrid
  static const _axisLabel = Color(0xFFA0AEB6); // AppColors.wreck.textSecondary

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    final layout = _chartLayout(size, series);

    const labelStyle = TextStyle(
      fontFamily: 'JetBrainsMono',
      fontSize: 9,
      color: _axisLabel,
      height: 1.0,
    );

    final gridPaint = Paint()
      ..color = _gridColor
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = theme.colorScheme.outline
      ..strokeWidth = 1;

    // ── mV grid + labels ─────────────────────────────────────────────
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
        text: TextSpan(text: v.toStringAsFixed(decimals), style: labelStyle),
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

    // ── Date axis (4 ticks evenly across the time span) ───────────────
    const dateTicks = 3; // 4 labels: i = 0..3
    for (var i = 0; i <= dateTicks; i++) {
      final frac = i / dateTicks;
      final t = layout.minTime + frac * layout.timeRange;
      final x = layout.xAt(t);
      final tp = TextPainter(
        text: TextSpan(
          text: _formatMonthYear(
              DateTime.fromMillisecondsSinceEpoch(t.round())),
          style: labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Left-align the first label, right-align the last, centre the rest,
      // so nothing overflows the plot edges.
      double lx;
      if (i == 0) {
        lx = x;
      } else if (i == dateTicks) {
        lx = x - tp.width;
      } else {
        lx = x - tp.width / 2;
      }
      tp.paint(canvas,
          Offset(lx, _ChartLayout.top + layout.plotH + 6));
    }

    // ── Axes ─────────────────────────────────────────────────────────
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

    // ── Trend line + dots ────────────────────────────────────────────
    final linePaint = Paint()
      ..color = theme.colorScheme.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    final dotPaint = Paint()..color = theme.colorScheme.primary;
    final selectedPaint = Paint()..color = theme.colorScheme.error;

    final path = Path()..moveTo(layout.pointAt(0).dx, layout.pointAt(0).dy);
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

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.series != series ||
      old.theme != theme ||
      old.selectedIndex != selectedIndex;
}

class _Tooltip extends StatelessWidget {
  final ({DateTime date, double mv, String diveId}) point;
  final int diveNumberInSeries;
  final VoidCallback? onTap;

  const _Tooltip({
    required this.point,
    required this.diveNumberInSeries,
    this.onTap,
  });

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
