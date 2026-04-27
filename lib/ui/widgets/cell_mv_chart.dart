import 'package:flutter/material.dart';

class CellMvChart extends StatelessWidget {
  final List<({DateTime date, double mv, String diveId})> series;
  final double height;

  const CellMvChart({super.key, required this.series, this.height = 220});

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('No surface-mV data yet')),
      );
    }
    return SizedBox(
      height: height,
      child: CustomPaint(painter: _ChartPainter(series, Theme.of(context))),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<({DateTime date, double mv, String diveId})> series;
  final ThemeData theme;

  _ChartPainter(this.series, this.theme);

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    final minTime = series.first.date.millisecondsSinceEpoch;
    final maxTime = series.last.date.millisecondsSinceEpoch;
    final minMv = series.map((p) => p.mv).reduce((a, b) => a < b ? a : b);
    final maxMv = series.map((p) => p.mv).reduce((a, b) => a > b ? a : b);
    final timeRange =
        (maxTime - minTime).clamp(1, double.infinity).toDouble();
    final mvRange = (maxMv - minMv).clamp(1.0, double.infinity);

    const pad = 24.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;

    final axisPaint = Paint()
      ..color = theme.colorScheme.outline
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(pad, pad), Offset(pad, pad + h), axisPaint);
    canvas.drawLine(
        Offset(pad, pad + h), Offset(pad + w, pad + h), axisPaint);

    final linePaint = Paint()
      ..color = theme.colorScheme.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()..color = theme.colorScheme.primary;

    Offset xy(int i) {
      final t = series[i].date.millisecondsSinceEpoch;
      final x = pad + ((t - minTime) / timeRange) * w;
      final y = pad + h - ((series[i].mv - minMv) / mvRange) * h;
      return Offset(x, y);
    }

    final path = Path();
    path.moveTo(xy(0).dx, xy(0).dy);
    for (var i = 1; i < series.length; i++) {
      path.lineTo(xy(i).dx, xy(i).dy);
    }
    canvas.drawPath(path, linePaint);
    for (var i = 0; i < series.length; i++) {
      canvas.drawCircle(xy(i), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.series != series || old.theme != theme;
}
