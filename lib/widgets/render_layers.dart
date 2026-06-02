import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Forces a save-layer so sibling children inside a [Stack] can composite
/// with non-srcOver blend modes against each other instead of against the
/// background.
class SaveLayer extends SingleChildRenderObjectWidget {
  const SaveLayer({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _SaveLayerRender();
}

class _SaveLayerRender extends RenderProxyBox {
  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    context.canvas.saveLayer(offset & size, Paint());
    context.paintChild(child!, offset);
    context.canvas.restore();
  }
}

/// Applies a [BlendMode] to its child. Must be used inside a parent that
/// establishes a compositing layer (e.g. [SaveLayer]).
class BlendMask extends SingleChildRenderObjectWidget {
  final BlendMode blendMode;
  const BlendMask({super.key, required this.blendMode, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _BlendMaskRender()..blendMode = blendMode;

  @override
  void updateRenderObject(BuildContext context, _BlendMaskRender renderObject) {
    renderObject.blendMode = blendMode;
  }
}

class _BlendMaskRender extends RenderProxyBox {
  BlendMode _blendMode = BlendMode.srcOver;
  BlendMode get blendMode => _blendMode;
  set blendMode(BlendMode value) {
    if (_blendMode == value) return;
    _blendMode = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    context.canvas.saveLayer(offset & size, Paint()..blendMode = _blendMode);
    context.paintChild(child!, offset);
    context.canvas.restore();
  }
}
