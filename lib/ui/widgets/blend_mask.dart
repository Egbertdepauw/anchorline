/// Composites a child using a chosen [BlendMode] against its parent's
/// pixels, at the chosen alpha. Use to apply blend modes (e.g. screen,
/// plus) that Flutter's stock `Image.asset(colorBlendMode:)` can't
/// reach — those blend the image with a colour, not with what's behind
/// it.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class BlendMask extends SingleChildRenderObjectWidget {
  final BlendMode blendMode;
  final double opacity;

  const BlendMask({
    super.key,
    required this.blendMode,
    required this.opacity,
    super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBlendMask(blendMode, opacity);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final ro = renderObject as _RenderBlendMask;
    ro.blendMode = blendMode;
    ro.opacity = opacity;
  }
}

class _RenderBlendMask extends RenderProxyBox {
  BlendMode blendMode;
  double opacity;
  _RenderBlendMask(this.blendMode, this.opacity);

  @override
  void paint(PaintingContext context, Offset offset) {
    context.canvas.saveLayer(
      offset & size,
      Paint()
        ..blendMode = blendMode
        ..color = Color.fromRGBO(255, 255, 255, opacity),
    );
    super.paint(context, offset);
    context.canvas.restore();
  }
}
