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
class _ChartLayout {
  final Size size;
  final List<({DateTime date, double mv, String diveId})> series;
  late final double minTime;
  late final double maxTime;
  late final double minMv;
  late final double maxMv;
  late final double timeRange;
  late final double mvRange;

  static const double pad = 24.0;

  _ChartLayout(this.size, this.series) {
    minTime = series.first.date.millisecondsSinceEpoch.toDouble();
    maxTime = series.last.date.millisecondsSinceEpoch.toDouble();
    final mvs = series.map((p) => p.mv);
    minMv = mvs.reduce(math.min);
    maxMv = mvs.reduce(math.max);
    timeRange = (maxTime - minTime).clamp(1, double.infinity).toDouble();
    mvRange = (maxMv - minMv).clamp(1.0, double.infinity);
  }

  double get plotW => size.width - pad * 2;
  double get plotH => size.height - pad * 2;

  Offset pointAt(int i) {
    final t = series[i].date.millisecondsSinceEpoch;
    final x = pad + ((t - minTime) / timeRange) * plotW;
    final y = pad + plotH - ((series[i].mv - minMv) / mvRange) * plotH;
    return Offset(x, y);
  }
}

_ChartLayout _chartLayout(
  Size size,
  List<({DateTime date, double mv, String diveId})> series,
) =>
    _ChartLayout(size, series);

class _ChartPainter extends CustomPainter {
  final List<({DateTime date, double mv, String diveId})> series;
  final ThemeData theme;
  final int? selectedIndex;

  _ChartPainter(this.series, this.theme, this.selectedIndex);

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    final layout = _chartLayout(size, series);

    final axisPaint = Paint()
      ..color = theme.colorScheme.outline
      ..strokeWidth = 1;
    canvas.drawLine(
      const Offset(_ChartLayout.pad, _ChartLayout.pad),
      Offset(_ChartLayout.pad, _ChartLayout.pad + layout.plotH),
      axisPaint,
    );
    canvas.drawLine(
      Offset(_ChartLayout.pad, _ChartLayout.pad + layout.plotH),
      Offset(
        _ChartLayout.pad + layout.plotW,
        _ChartLayout.pad + layout.plotH,
      ),
      axisPaint,
    );

    final linePaint = Paint()
      ..color = theme.colorScheme.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
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
