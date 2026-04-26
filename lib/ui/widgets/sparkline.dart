import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class DepthSparkline extends StatelessWidget {
  final Float32List depths;
  final Color color;

  const DepthSparkline({super.key, required this.depths, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparklinePainter(depths: downsampleDepth(depths, 30), color: color),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final Float32List depths;
  final Color color;

  _SparklinePainter({required this.depths, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (depths.length < 2) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    var maxDepth = 0.0;
    for (final d in depths) {
      if (d > maxDepth) maxDepth = d;
    }
    if (maxDepth == 0) return;

    final path = ui.Path();
    final xStep = size.width / (depths.length - 1);
    const padding = 2.0;
    final yScale = (size.height - padding * 2) / maxDepth;

    for (var i = 0; i < depths.length; i++) {
      final x = i * xStep;
      final y = padding + depths[i] * yScale;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.depths != depths || old.color != color;
}

Float32List downsampleDepth(Float32List data, int maxPoints) {
  if (data.length <= maxPoints) return data;
  final step = data.length / maxPoints;
  final result = Float32List(maxPoints);
  for (var i = 0; i < maxPoints; i++) {
    result[i] = data[(i * step).floor()];
  }
  return result;
}
