/// Renders a subtle CCR-diver watermark behind a screen's content. The
/// asset is a transparent-background PNG so a plain Opacity composite is
/// all that's needed.
library;

import 'package:flutter/material.dart';

class BackgroundWatermark extends StatelessWidget {
  final Widget child;
  final double opacity;

  const BackgroundWatermark({
    super.key,
    required this.child,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    if (opacity <= 0) return child;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: FractionallySizedBox(
                widthFactor: 0.9,
                heightFactor: 0.9,
                child: Opacity(
                  opacity: opacity,
                  child: Image.asset(
                    'assets/images/watermark.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
