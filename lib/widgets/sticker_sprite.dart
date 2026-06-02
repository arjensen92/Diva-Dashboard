import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'holographic.dart';
import 'render_layers.dart';

/// Gachadex-grid sticker — the gachamon sprite rendered with a dynamic
/// white silhouette/border dilated outward from its own alpha, plus the
/// card texture overlaid (masked to the silhouette) on top of that white,
/// then the original sprite painted in front. When [isHolo] is true a
/// holographic shimmer plays inside the sprite's alpha (not on the
/// border).
class StickerSprite extends StatefulWidget {
  final String spritePath;
  final bool isHolo;
  final double outlineRadius;
  const StickerSprite({
    super.key,
    required this.spritePath,
    this.isHolo = false,
    this.outlineRadius = 5.0,
  });

  @override
  State<StickerSprite> createState() => _StickerSpriteState();
}

class _StickerSpriteState extends State<StickerSprite> {
  ui.Image? _image;
  String? _loadedPath;

  @override
  void initState() {
    super.initState();
    _loadImage();
    if (widget.isHolo) HoloClock.instance.addListener(_onTick);
  }

  @override
  void didUpdateWidget(covariant StickerSprite old) {
    super.didUpdateWidget(old);
    if (old.spritePath != widget.spritePath) {
      _image?.dispose();
      _image = null;
      _loadedPath = null;
      _loadImage();
    }
    if (old.isHolo != widget.isHolo) {
      if (old.isHolo) HoloClock.instance.removeListener(_onTick);
      if (widget.isHolo) HoloClock.instance.addListener(_onTick);
    }
  }

  @override
  void dispose() {
    if (widget.isHolo) HoloClock.instance.removeListener(_onTick);
    _image?.dispose();
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  Future<void> _loadImage() async {
    final path = widget.spritePath;
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      if (widget.spritePath != path) return; // path changed while loading
      setState(() {
        _image?.dispose();
        _image = frame.image;
        _loadedPath = path;
      });
    } catch (_) {
      // Swallow — sticker silently disappears if the sprite file is
      // missing or can't be decoded.
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    if (img == null || _loadedPath != widget.spritePath) {
      return const SizedBox.shrink();
    }
    const blobBasePeriodSec = 240.0;
    final auraPhase = widget.isHolo
        ? (HoloClock.instance.seconds / blobBasePeriodSec) % 1.0
        : 0.0;
    // Wrap in SaveLayer so the sticker composites against a fresh
    // transparent backdrop rather than whatever the parent canvas
    // already has in our rect. Without this, the aura's srcATop step
    // would see the dashboard card / grid tile background as opaque
    // destination alpha everywhere, and fill the widget rect as a
    // box. (Placed stickers work for the same reason — their Opacity
    // wrapper pushes an equivalent isolating layer.)
    return SaveLayer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _StickerPainter(
          image: img,
          outlineRadius: widget.outlineRadius,
          isHolo: widget.isHolo,
          auraPhase: auraPhase,
        ),
      ),
    );
  }
}

/// Paints a single Gachamon sticker — white dilated outline, sprite, optional
/// holo aura — onto [canvas] within the local rect [Offset.zero & size].
///
/// The caller MUST wrap this call in a canvas.saveLayer so the srcATop blend
/// in the holo aura composites against the sticker's own accumulated alpha
/// rather than the underlying background. [StickerSprite] provides this via
/// the [SaveLayer] widget; [DashboardStickerLayer] provides it via an explicit
/// canvas.saveLayer() call per sticker in the layer painter.
void paintStickerToCanvas(
  Canvas canvas,
  ui.Image image,
  Size size, {
  double outlineRadius = 5.0,
  bool isHolo = false,
  double auraPhase = 0.0,
}) {
  // BoxFit.contain the sprite into an inset so the white outline has
  // room to grow outward without being clipped.
  final pad = outlineRadius + 2;
  final innerW = (size.width - 2 * pad).clamp(0.0, double.infinity);
  final innerH = (size.height - 2 * pad).clamp(0.0, double.infinity);
  final imgW = image.width.toDouble();
  final imgH = image.height.toDouble();
  final scale = math.min(innerW / imgW, innerH / imgH);
  final drawW = imgW * scale;
  final drawH = imgH * scale;
  final dst = Rect.fromLTWH(
    (size.width - drawW) / 2,
    (size.height - drawH) / 2,
    drawW,
    drawH,
  );
  final src = Rect.fromLTWH(0, 0, imgW, imgH);
  final bounds = Offset.zero & size;

  canvas.save();
  canvas.clipRect(bounds);

  // FilterQuality.medium = bilinear-ish. Default is `none` (nearest
  // neighbor), which looks jagged at 40–64 px — these sprites aren't
  // pixel art.
  final imagePaint = Paint()..filterQuality = FilterQuality.medium;

  // 1) White silhouette via multi-stamp outlining.
  // Two rings — outer at [outlineRadius] with 12 stamps (30° apart),
  // inner at half radius with 4 staggered stamps — fill gaps on thin
  // features that a single outer ring would leave as visible
  // "splinters". Was 24+8 originally; halved to 12+4 because Skia's
  // anti-aliasing covers the larger angular gap and the per-cell paint
  // budget on the dex grid is the dominant lag source. Saves ~50% of
  // outline draw calls per sprite.
  final whitePaint = Paint()
    ..filterQuality = FilterQuality.medium
    ..colorFilter = const ColorFilter.mode(Colors.white, BlendMode.srcATop);
  const outerStamps = 12;
  const innerStamps = 4;
  for (int i = 0; i < outerStamps; i++) {
    final angle = i * 2 * math.pi / outerStamps;
    canvas.drawImageRect(
      image, src,
      dst.shift(Offset(math.cos(angle) * outlineRadius, math.sin(angle) * outlineRadius)),
      whitePaint,
    );
  }
  for (int i = 0; i < innerStamps; i++) {
    final angle = (i + 0.5) * 2 * math.pi / innerStamps;
    canvas.drawImageRect(
      image, src,
      dst.shift(Offset(math.cos(angle) * outlineRadius * 0.5, math.sin(angle) * outlineRadius * 0.5)),
      whitePaint,
    );
  }

  // 2) Sprite on top of the silhouette.
  canvas.drawImageRect(image, src, dst, imagePaint);

  // 3) Holo aura LAST. Wrap in srcATop saveLayer so blobs composite
  // normally amongst themselves, then the whole shimmer is clipped in
  // one pass to the sticker's accumulated alpha.
  if (isHolo) {
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.srcATop);
    HoloPainter(phase: auraPhase).paint(canvas, size);
    canvas.restore();
  }

  canvas.restore();
}

/// Renders a single sticker — white dilated outline, optional holo aura
/// masked to that outline, and the sprite on top — in ONE CustomPainter.
/// Delegates all logic to [paintStickerToCanvas]; see that function for
/// details on the blend-mode isolation requirement.
class _StickerPainter extends CustomPainter {
  final ui.Image image;
  final double outlineRadius;
  final bool isHolo;
  final double auraPhase;
  _StickerPainter({
    required this.image,
    required this.outlineRadius,
    required this.isHolo,
    required this.auraPhase,
  });

  @override
  void paint(Canvas canvas, Size size) => paintStickerToCanvas(
        canvas, image, size,
        outlineRadius: outlineRadius,
        isHolo: isHolo,
        auraPhase: auraPhase,
      );

  @override
  bool shouldRepaint(covariant _StickerPainter old) =>
      old.image != image ||
      old.outlineRadius != outlineRadius ||
      old.isHolo != isHolo ||
      old.auraPhase != auraPhase;
}
