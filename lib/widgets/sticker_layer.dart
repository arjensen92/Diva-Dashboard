import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/overlay_service.dart';
import 'animated_frame.dart';
import 'holographic.dart';
import 'sticker_panel_widgets.dart' show DraggableSticker;
import 'sticker_sprite.dart' show paintStickerToCanvas;

// ── Path helpers ─────────────────────────────────────────────────────────────

/// Paths that should never be rotated regardless of their stored rotation.
const _noRotate = ['adfad1', 'c134vdfa`', 'aaaaaaaa'];

/// True when a sticker path looks like a gachamon sprite — i.e. it
/// lives under `assets/gachamon/` and inside one of the per-generation
/// or form subfolders. Triggers the outline + holo shimmer pipeline.
/// Anything else is a plain decorative graphic and renders without
/// the outline pass.
bool _isGachamon(String path) =>
    path.contains('gachamon') &&
    (path.contains('generation_') ||
        path.contains('alt_forms') ||
        path.contains('alolan_forms') ||
        path.contains('galarian_forms') ||
        path.contains('hisuian_forms') ||
        path.contains('paldean_forms') ||
        path.contains('mega_evolutions') ||
        path.contains('gigantamax'));

// ── DashboardStickerLayer ────────────────────────────────────────────────────

/// Single-pass painter for all placed dashboard stickers (graphics +
/// Gachamon sprites). Replaces the per-sticker widget stack that created
/// one [SaveLayer], one [CustomPaint], one [AnimationController], and one
/// [HoloClock] listener per sticker.
///
/// Architecture:
/// • ONE [HoloClock] listener drives holo shimmer, bobbing, and GIF frame
///   cycling for the entire layer — regardless of sticker count.
/// • ONE [CustomPainter] draws every sticker in a single rasterisation pass.
/// • Invisible [DraggableSticker] hit zones (no visual content) are layered
///   on top via [Positioned], one per visible sticker, so gesture routing
///   behaves identically to before: sticker areas absorb touches, empty
///   areas fall through to the [PageView] carousel below.
/// • Images are decoded once per unique file path and shared across all
///   stickers that reference the same path.
/// • Off-screen stickers (outside the visible carousel viewport) receive no
///   frame ticks and consume no animation CPU.
class DashboardStickerLayer extends StatefulWidget {
  /// All placed stickers from [graphicsImagesProvider]. Mutable — positions
  /// are updated in-place during drag without re-assigning the list.
  final List<PlacedOverlay> stickers;

  /// Set of sprite file paths that should receive the holographic shimmer.
  final Set<String> holoPaths;

  /// Current [PageController.page] value — used to convert canvas-relative
  /// sticker x-coordinates to screen x-coordinates.
  final double scrollOffset;

  /// Number of card pages (for canvas x modulo).
  final int numCards;

  const DashboardStickerLayer({
    super.key,
    required this.stickers,
    required this.holoPaths,
    required this.scrollOffset,
    required this.numCards,
  });

  @override
  State<DashboardStickerLayer> createState() => _DashboardStickerLayerState();
}

class _DashboardStickerLayerState extends State<DashboardStickerLayer> {
  /// path → decoded frame, shared across all stickers at that path.
  final Map<String, AnimatedFrame> _cache = {};
  final Set<String> _loading = {};

  /// Cached from the last build so the HoloClock listener can compute
  /// which paths are on-screen without calling MediaQuery.
  double _screenW = 0;
  double _cardPos = 0;

  double _lastClockSec = 0;

  @override
  void initState() {
    super.initState();
    HoloClock.instance.addListener(_onClock);
    _loadNewImages();
  }

  @override
  void didUpdateWidget(covariant DashboardStickerLayer old) {
    super.didUpdateWidget(old);
    if (widget.stickers != old.stickers) {
      _evictStale();
      _loadNewImages();
    }
  }

  @override
  void dispose() {
    HoloClock.instance.removeListener(_onClock);
    for (final f in _cache.values) {
      f.dispose();
    }
    super.dispose();
  }

  // ── Clock / frame ticking ─────────────────────────────────────────────────

  void _onClock() {
    if (!mounted) return;
    final now = HoloClock.instance.seconds;
    final deltaMicros = ((now - _lastClockSec) * 1e6).round();
    final delta = Duration(microseconds: deltaMicros.clamp(0, 100000));
    _lastClockSec = now;

    // Advance GIF frames only for paths that are currently on-screen.
    // Off-screen stickers pause automatically — no wasted CPU.
    if (_screenW > 0) {
      final visiblePaths = _visiblePaths();
      for (final path in visiblePaths) {
        final frame = _cache[path];
        if (frame == null || !frame.tick(delta)) continue;
        frame.advance(() {
          if (mounted) setState(() {});
        });
      }
    }

    setState(() {}); // repaint for holo + bobbing
  }

  Set<String> _visiblePaths() {
    final result = <String>{};
    for (final s in widget.stickers) {
      final screenX = (s.x - _cardPos) * _screenW;
      final renderSize = _isGachamon(s.path) ? s.size * 1.45 : s.size;
      if (screenX >= -renderSize - _screenW * 0.5 &&
          screenX <= _screenW * 1.5) {
        result.add(s.path);
      }
    }
    return result;
  }

  // ── Image loading ─────────────────────────────────────────────────────────

  void _loadNewImages() {
    for (final s in widget.stickers) {
      _loadImage(s.path);
    }
  }

  Future<void> _loadImage(String path) async {
    if (_cache.containsKey(path) || _loading.contains(path)) { return; }
    _loading.add(path);
    // Decode at display size — stickers render at ≤256 px; avoids holding the
    // full native sprite resolution (often 512–1024 px) in GPU memory.
    final frame = await AnimatedFrame.load(
      path,
      targetWidth: 256,
      targetHeight: 256,
    );
    _loading.remove(path);
    if (!mounted || frame == null) { return; }
    _cache[path] = frame;
    setState(() {});
  }

  /// Dispose and remove cache entries for paths no longer in [widget.stickers].
  void _evictStale() {
    final activePaths = {for (final s in widget.stickers) s.path};
    final stale = _cache.keys.where((p) => !activePaths.contains(p)).toList();
    for (final p in stale) {
      _cache.remove(p)?.dispose();
      _loading.remove(p);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    _screenW = size.width;
    _cardPos = widget.scrollOffset % widget.numCards;

    final clockSec = HoloClock.instance.seconds;
    final hitZones = <Widget>[];

    for (int i = 0; i < widget.stickers.length; i++) {
      final s = widget.stickers[i];
      final screenX = (s.x - _cardPos) * _screenW;
      final screenH = size.height;
      final isGachamon = _isGachamon(s.path);
      final renderSize = isGachamon ? s.size * 1.45 : s.size;

      // Cull stickers outside the visible viewport — no hit zone or tick.
      if (screenX < -renderSize - _screenW * 0.5 ||
          screenX > _screenW * 1.5) {
        continue;
      }

      // Bobbing Y offset for Gachamon stickers.
      double bobY = 0;
      if (isGachamon) {
        final phase = (s.path.hashCode.abs() % 1000) / 1000.0 * 2 * math.pi;
        bobY = math.sin((clockSec / 1.8) * 2 * math.pi + phase) * 3.0;
      }

      final top = s.y * screenH + bobY;

      // Invisible hit zone — absorbs gestures within the sticker bounds so
      // touches don't fall through to the PageView carousel below.
      // ObjectKey on the PlacedOverlay instance keeps each hit zone's
      // DraggableSticker element alive across 60fps HoloClock rebuilds and
      // — critically — stays UNIQUE even when a small graphics folder makes
      // the same `s.path` get placed many times. (ValueKey(s.path) would
      // collide, and Flutter dropped overlapping-key hit zones, breaking
      // card taps and sticker drags.)
      hitZones.add(Positioned(
        key: ObjectKey(s),
        left: screenX,
        top: top,
        width: renderSize,
        height: renderSize,
        child: DraggableSticker(
          onDrag: (dx, dy) => setState(() {
            s.x += dx / _screenW;
            s.y += dy / size.height;
          }),
          onRotate: (dr) => setState(() {
            s.rotation += dr * 180 / math.pi;
          }),
          onResize: (ds) => setState(() {
            s.size = (s.size * ds).clamp(30, 500);
          }),
          child: const SizedBox.expand(),
        ),
      ));
    }

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // Visual layer — all stickers in one painter pass.
        // IgnorePointer ensures the CustomPaint is always transparent to hits;
        // gestures route exclusively through the DraggableSticker hit zones below.
        IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: _StickerLayerPainter(
                stickers: widget.stickers,
                cache: _cache,
                holoPaths: widget.holoPaths,
                cardPos: _cardPos,
                clockSec: clockSec,
                screenW: _screenW,
                screenH: size.height,
              ),
            ),
          ),
        ),
        // Hit zones — thin invisible gesture sinks, one per visible sticker.
        ...hitZones,
      ],
    );
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────

class _StickerLayerPainter extends CustomPainter {
  final List<PlacedOverlay> stickers;
  final Map<String, AnimatedFrame> cache;
  final Set<String> holoPaths;
  final double cardPos;
  final double clockSec;
  final double screenW;
  final double screenH;

  static const double _blobPeriod = 240.0;
  static const double _bobPeriod = 1.8;
  static const double _bobAmplitude = 3.0;

  _StickerLayerPainter({
    required this.stickers,
    required this.cache,
    required this.holoPaths,
    required this.cardPos,
    required this.clockSec,
    required this.screenW,
    required this.screenH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in stickers) {
      final frame = cache[s.path];
      if (frame == null) { continue; }

      final screenX = (s.x - cardPos) * screenW;
      final isGachamon = _isGachamon(s.path);
      final renderSize = isGachamon ? s.size * 1.45 : s.size;

      // Visibility cull — matches the hit-zone cull in build().
      if (screenX < -renderSize - screenW * 0.5 ||
          screenX > screenW * 1.5) {
        continue;
      }

      double bobY = 0;
      if (isGachamon) {
        final phase = (s.path.hashCode.abs() % 1000) / 1000.0 * 2 * math.pi;
        bobY = math.sin((clockSec / _bobPeriod) * 2 * math.pi + phase) * _bobAmplitude;
      }

      final screenY = s.y * screenH + bobY;
      final rotation = _noRotate.any((f) => s.path.contains(f))
          ? 0.0
          : s.rotation * math.pi / 180.0;

      canvas.save();
      canvas.translate(screenX + renderSize / 2, screenY + renderSize / 2);
      if (rotation != 0) canvas.rotate(rotation);
      canvas.translate(-renderSize / 2, -renderSize / 2);

      if (isGachamon) {
        // saveLayer provides both the compositing isolation that paintStickerToCanvas
        // requires (for srcATop blend) and the 0.7 opacity in one call.
        canvas.saveLayer(
          Rect.fromLTWH(0, 0, renderSize, renderSize),
          Paint()..color = const Color(0xB3FFFFFF), // 0.7 alpha
        );
        final isHolo = holoPaths.contains(s.path);
        paintStickerToCanvas(
          canvas,
          frame.current,
          Size(renderSize, renderSize),
          outlineRadius: renderSize * 0.025,
          isHolo: isHolo,
          auraPhase: isHolo ? (clockSec / _blobPeriod) % 1.0 : 0.0,
        );
        canvas.restore(); // saveLayer
      } else {
        // Plain graphic sticker — no blend modes, just alpha in the paint.
        // Avoids a saveLayer entirely, which is cheaper than Opacity widget.
        // Destination rect is BoxFit.contain inside the renderSize square,
        // so off-aspect graphics (wide banners, tall logos) keep their
        // natural proportions instead of being squashed to a square.
        final img = frame.current;
        final imgW = img.width.toDouble();
        final imgH = img.height.toDouble();
        final fitScale = math.min(renderSize / imgW, renderSize / imgH);
        final dw = imgW * fitScale;
        final dh = imgH * fitScale;
        final dx = (renderSize - dw) / 2;
        final dy = (renderSize - dh) / 2;
        canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, imgW, imgH),
          Rect.fromLTWH(dx, dy, dw, dh),
          Paint()
            ..filterQuality = FilterQuality.low
            ..color = const Color(0xB3FFFFFF), // 0.7 alpha
        );
      }

      canvas.restore(); // translate + rotate
    }
  }

  @override
  bool shouldRepaint(covariant _StickerLayerPainter old) =>
      old.clockSec != clockSec ||
      old.stickers != stickers ||
      old.cardPos != cardPos ||
      old.screenW != screenW ||
      old.screenH != screenH ||
      old.holoPaths != holoPaths;
}
