import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Which mV metric the chart is showing.
enum CellMvMetric { surface, peak }

class CellMvChart extends StatefulWidget {
  final List<({DateTime date, double mv, String diveId})> surfaceSeries;
  final List<({DateTime date, double mv, String diveId})> peakSeries;

  /// Peak-mV baseline (max peak of the first 5 dives, from CellHealth). When
  /// non-null, the peak view draws the BASELINE / WATCH (0.85x) / REPLACE
  /// (0.70x) reference lines. Null (fewer than 5 dives) => no reference lines.
  final double? baselinePeakMv;

  /// Peak-mV recent ceiling (max peak of the last 5 dives, from CellHealth).
  /// Drawn as the RECENT line, coloured by where it lands relative to the
  /// thresholds — this is the value the health verdict actually compares
  /// against [baselinePeakMv].
  final double? recentPeakMv;
  final double height;
  final void Function(String diveId)? onDiveTap;

  const CellMvChart({
    super.key,
    required this.surfaceSeries,
    required this.peakSeries,
    this.baselinePeakMv,
    this.recentPeakMv,
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

  // Reference lines apply to the peak view only, and only with a baseline.
  double? get _baseline =>
      _metric == CellMvMetric.peak ? widget.baselinePeakMv : null;
  double? get _recent =>
      _metric == CellMvMetric.peak ? widget.recentPeakMv : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<CellMvMetric>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                        value: CellMvMetric.surface,
                        label: Text('Surface mV')),
                    ButtonSegment(
                        value: CellMvMetric.peak, label: Text('Peak mV')),
                  ],
                  selected: {_metric},
                  onSelectionChanged: (s) => setState(() {
                    _metric = s.first;
                    _selectedIndex = null;
                  }),
                ),
              ),
            ),
            IconButton(
              onPressed: () => _showHelp(context),
              icon: const Icon(Icons.help_outline),
              iconSize: 20,
              visualDensity: VisualDensity.compact,
              tooltip: 'How to read this',
            ),
          ],
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
                                _recent,
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

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final t = Theme.of(ctx);
        final body = t.textTheme.bodyMedium;
        return AlertDialog(
          title: const Text('Reading cell health'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    "This tracks the cell's peak mV — the highest reading on "
                    'each dive, hit near your setpoint at depth.',
                    style: body),
                const SizedBox(height: 12),
                Text('Health compares two ceilings:', style: body),
                const SizedBox(height: 4),
                Text('•  BASELINE — best peak of the first 5 dives.',
                    style: body),
                Text('•  RECENT — best peak of the last 5 dives.', style: body),
                const SizedBox(height: 12),
                Text(
                    'Healthy if RECENT is at least 85% of BASELINE (on or above '
                    'the WATCH line). Watch if at least 70% (above REPLACE). '
                    'Replace below that.',
                    style: body),
                const SizedBox(height: 12),
                Text(
                    "Individual dips don't count against the cell — "
                    'low-setpoint, short, or surface-flushed dives simply never '
                    'push it to its ceiling. What matters is that it can still '
                    'reach a high peak recently.',
                    style: body),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Got it'),
            ),
          ],
        );
      },
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

  static const double left = 56.0;
  static const double right = 14.0;
  static const double top = 16.0;
  static const double bottom = 28.0;

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

/// One horizontal reference line on the peak view.
typedef _Ref = ({double mv, Color color, String label, bool dashed});

class _ChartPainter extends CustomPainter {
  final List<({DateTime date, double mv, String diveId})> series;
  final ThemeData theme;
  final int? selectedIndex;
  final double? baseline;
  final double? recent;

  _ChartPainter(
      this.series, this.theme, this.selectedIndex, this.baseline, this.recent);

  static const _gridColor = Color(0xFF1A2832); // AppColors.wreck.chartGrid
  static const _axisLabel = Color(0xFFA0AEB6); // AppColors.wreck.textSecondary
  static const _healthyColor = Color(0xFF4ADE80); // AppColors.wreck.statusSuccess
  static const _watchColor = Color(0xFFF39C12); // AppColors.wreck.statusWarning
  static const _replaceColor = Color(0xFFE74C3C); // AppColors.wreck.statusDanger
  static const _pillBg = Color(0xCC0A1518); // AppColors.wreck.surfaceBg @ ~80%

  static const _labelStyle = TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: 11,
    color: _axisLabel,
    height: 1.0,
  );

  /// Colour of the RECENT line: where the recent ceiling lands against the
  /// baseline drives the Healthy / Watch / Replace verdict.
  static Color _recentColor(double recent, double base) {
    final ratio = recent / base;
    if (ratio >= 0.85) return _healthyColor;
    if (ratio >= 0.70) return _watchColor;
    return _replaceColor;
  }

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

    // ── mV grid + numeric labels ─────────────────────────────────────
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
          Offset(_ChartLayout.left - tp.width - 8, y - tp.height / 2));
    }

    // ── "mV" axis title, rotated up the left gutter ──────────────────
    final titleTp = TextPainter(
      text: const TextSpan(text: 'mV', style: _labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(12, _ChartLayout.top + layout.plotH / 2);
    canvas.rotate(-math.pi / 2);
    titleTp.paint(canvas, Offset(-titleTp.width / 2, -titleTp.height / 2));
    canvas.restore();

    // ── Date axis (4 ticks evenly across the time span) ──────────────
    const dateTicks = 3; // 4 labels: i = 0..3
    for (var i = 0; i <= dateTicks; i++) {
      final frac = i / dateTicks;
      final t = layout.minTime + frac * layout.timeRange;
      final x = layout.xAt(t);
      final tp = TextPainter(
        text: TextSpan(
          text:
              _formatMonthYear(DateTime.fromMillisecondsSinceEpoch(t.round())),
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
      tp.paint(canvas, Offset(lx, _ChartLayout.top + layout.plotH + 8));
    }

    // ── Reference lines (peak view with a baseline) ──────────────────
    // Build the set, then draw the lines now (under the data) and the
    // labels later (over the data, so they stay legible).
    final refs = <_Ref>[];
    final b = baseline;
    if (b != null && b > 0) {
      void addRef(double mv, Color c, String label, bool dashed) {
        if (mv >= layout.niceMinMv && mv <= layout.niceMaxMv) {
          refs.add((mv: mv, color: c, label: label, dashed: dashed));
        }
      }

      addRef(b, _axisLabel, 'BASELINE ${b.round()}', false);
      final rec = recent;
      if (rec != null && rec > 0) {
        addRef(rec, _recentColor(rec, b), 'RECENT ${rec.round()}', false);
      }
      addRef(b * 0.85, _watchColor, 'WATCH ${(b * 0.85).round()}', true);
      addRef(b * 0.70, _replaceColor, 'REPLACE ${(b * 0.70).round()}', true);

      for (final r in refs) {
        final y = layout.yAt(r.mv);
        final paint = Paint()
          ..color = r.color
          ..strokeWidth = r.dashed ? 1 : 1.5;
        final x0 = _ChartLayout.left;
        final x1 = _ChartLayout.left + layout.plotW;
        if (r.dashed) {
          _drawDashedLine(canvas, Offset(x0, y), Offset(x1, y), paint,
              dashWidth: 5, gapWidth: 4);
        } else {
          canvas.drawLine(Offset(x0, y), Offset(x1, y), paint);
        }
      }
    }

    // ── Axes ─────────────────────────────────────────────────────────
    canvas.drawLine(
      const Offset(_ChartLayout.left, _ChartLayout.top),
      Offset(_ChartLayout.left, _ChartLayout.top + layout.plotH),
      axisPaint,
    );
    canvas.drawLine(
      Offset(_ChartLayout.left, _ChartLayout.top + layout.plotH),
      Offset(
          _ChartLayout.left + layout.plotW, _ChartLayout.top + layout.plotH),
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

    // ── Reference labels, on top of everything, de-collided ──────────
    _drawRefLabels(canvas, layout, refs);
  }

  /// Left-aligned label pills for the reference lines, anchored just inside
  /// the Y-axis so they sit over the cell's earliest dives rather than the
  /// recent ones that drive the verdict. Pills are nudged downward so
  /// neighbouring labels (e.g. RECENT just above WATCH) don't overlap, while
  /// the lines themselves stay at their true mV.
  void _drawRefLabels(Canvas canvas, _ChartLayout layout, List<_Ref> refs) {
    if (refs.isEmpty) return;
    final items = <({double y, TextPainter tp, Color color})>[];
    for (final r in refs) {
      final tp = TextPainter(
        text: TextSpan(
          text: r.label,
          style: _labelStyle.copyWith(
              color: r.color, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      items.add((y: layout.yAt(r.mv) - tp.height / 2, tp: tp, color: r.color));
    }
    items.sort((a, b) => a.y.compareTo(b.y));

    const x = _ChartLayout.left + 6;
    double? prevBottom;
    for (final it in items) {
      var y = it.y;
      if (prevBottom != null && y < prevBottom + 1) y = prevBottom + 1;
      final rect = Rect.fromLTWH(x - 4, y - 2, it.tp.width + 8, it.tp.height + 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..color = _pillBg,
      );
      it.tp.paint(canvas, Offset(x, y));
      prevBottom = y + it.tp.height + 2;
    }
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
      old.baseline != baseline ||
      old.recent != recent;
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
