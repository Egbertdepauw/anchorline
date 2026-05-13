/// Renders a subtle CCR-diver watermark behind a screen's content,
/// composited via BlendMode.screen so the asset's black background is
/// transparent and the white line art lifts onto the dark surface.
library;

import 'package:flutter/material.dart';

import 'blend_mask.dart';

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
                widthFactor: 0.6,
                heightFactor: 0.6,
                child: BlendMask(
                  blendMode: BlendMode.screen,
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
