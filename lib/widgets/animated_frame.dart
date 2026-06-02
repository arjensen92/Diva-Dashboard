import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

/// Decoded image state for one unique file path — handles both static images
/// (frameCount == 1) and animated GIFs / APNGs (frameCount > 1).
///
/// Path-keyed: each file is decoded ONCE regardless of how many stickers or
/// sparkles reference it. All references share the same [current] frame,
/// keeping peak decoded memory minimal.
///
/// Memory strategy:
/// • Static images (frameCount == 1): codec is disposed immediately after the
///   first frame is decoded. Only one [ui.Image] is held in memory.
/// • Animated images: codec is kept alive for [getNextFrame] cycling. It is
///   disposed in [dispose].
class AnimatedFrame {
  /// Non-null only for animated images; null for statics (disposed early).
  ui.Codec? _liveCodec;

  /// Cached separately so [tick] can check it without a live codec reference.
  final int frameCount;

  ui.Image current;
  Duration frameDuration;
  Duration sinceLastFrame = Duration.zero;

  AnimatedFrame._({
    required ui.Codec? liveCodec,
    required this.frameCount,
    required this.current,
    required this.frameDuration,
  }) : _liveCodec = liveCodec;

  /// Decode [path] from disk. Returns null on any error so callers can
  /// silently skip unreadable / missing files.
  ///
  /// [targetWidth] / [targetHeight] together specify a bounding box —
  /// the image is scaled to fit *within* that box while preserving its
  /// aspect ratio. Wide stickers stay wide, tall ones stay tall. For
  /// sparkles, 128×128 is plenty; for stickers, 256×256.
  ///
  /// Passing both directly to [ui.instantiateImageCodec] would force an
  /// exact target size and squash off-aspect images — that's the bug
  /// the bounding-box logic below is fixing.
  static Future<AnimatedFrame?> load(
    String path, {
    int? targetWidth,
    int? targetHeight,
  }) async {
    try {
      final bytes = await File(path).readAsBytes();

      // When a bounding box is requested, peek at the natural source size
      // via ImageDescriptor and scale proportionally so the decoded bitmap
      // keeps its aspect ratio. Skip when only one dimension is supplied
      // — the codec's single-axis scaling already preserves aspect.
      int? actualW = targetWidth;
      int? actualH = targetHeight;
      if (targetWidth != null && targetHeight != null) {
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        final srcW = descriptor.width;
        final srcH = descriptor.height;
        descriptor.dispose();
        buffer.dispose();
        if (srcW > 0 && srcH > 0) {
          // contain-fit scale, capped at 1.0 so we never upscale a
          // small source image (wastes memory, no quality benefit).
          final scale = math.min(
            math.min(targetWidth / srcW, targetHeight / srcH),
            1.0,
          );
          actualW = (srcW * scale).round().clamp(1, targetWidth);
          actualH = (srcH * scale).round().clamp(1, targetHeight);
        }
      }

      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: actualW,
        targetHeight: actualH,
      );
      final f = await codec.getNextFrame();
      final frames = codec.frameCount;
      final isAnimated = frames > 1;
      // For statics, drop the codec now — it holds the compressed bytes in
      // memory and we will never call getNextFrame again.
      if (!isAnimated) {
        codec.dispose();
      }
      return AnimatedFrame._(
        liveCodec: isAnimated ? codec : null,
        frameCount: frames,
        current: f.image,
        frameDuration: f.duration == Duration.zero
            ? const Duration(milliseconds: 100)
            : f.duration,
      );
    } catch (_) {
      return null;
    }
  }

  /// Accumulate [delta] elapsed time. Returns true when the next frame is due.
  bool tick(Duration delta) {
    if (frameCount <= 1) { return false; }
    sinceLastFrame += delta;
    return sinceLastFrame >= frameDuration;
  }

  /// Advance to the next frame. Only call after [tick] returns true.
  /// [onDone] is called on the main isolate once the new frame is decoded,
  /// so the caller can trigger a repaint.
  void advance(void Function()? onDone) {
    final codec = _liveCodec;
    if (codec == null) { return; }
    sinceLastFrame -= frameDuration;
    codec.getNextFrame().then((f) {
      current.dispose();
      current = f.image;
      frameDuration = f.duration == Duration.zero
          ? const Duration(milliseconds: 100)
          : f.duration;
      onDone?.call();
    });
  }

  void dispose() {
    current.dispose();
    _liveCodec?.dispose();
    _liveCodec = null;
  }
}
