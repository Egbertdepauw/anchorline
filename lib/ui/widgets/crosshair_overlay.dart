import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CrosshairOverlay extends StatelessWidget {
  final int sampleCount;
  final double chartLeftPad;
  final double chartRightPad;
  final ValueChanged<int> onIndexChanged;
  final VoidCallback onRelease;
  final Widget child;

  const CrosshairOverlay({
    super.key,
    required this.sampleCount,
    required this.chartLeftPad,
    required this.chartRightPad,
    required this.onIndexChanged,
    required this.onRelease,
    required this.child,
  });

  int _indexFromX(double x, double totalWidth) {
    final chartWidth = totalWidth - chartLeftPad - chartRightPad;
    if (chartWidth <= 0 || sampleCount < 2) return 0;
    final fraction = ((x - chartLeftPad) / chartWidth).clamp(0.0, 1.0);
    return (fraction * (sampleCount - 1)).round().clamp(0, sampleCount - 1);
  }

  void _onUpdate(Offset position, double width) {
    final index = _indexFromX(position.dx, width);
    HapticFeedback.selectionClick();
    onIndexChanged(index);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return GestureDetector(
        onLongPressStart: (details) =>
            _onUpdate(details.localPosition, constraints.maxWidth),
        onLongPressMoveUpdate: (details) =>
            _onUpdate(details.localPosition, constraints.maxWidth),
        onLongPressEnd: (_) => onRelease(),
        child: child,
      );
    });
  }
}
