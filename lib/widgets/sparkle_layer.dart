import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/dashboard_screen.dart';
import '../services/overlay_service.dart';
import 'animated_frame.dart';

/// Single-pass painter for all dashboard sparkle images. Replaces the old
/// [SparkleOverlay] which gave each of the 300–500 sparkles its own
/// [RepaintBoundary], [Image.file] decoder, and compositor layer.
///
/// Instead every unique file path is decoded ONCE into [AnimatedFrame]. All
/// sparkles referencing the same path share one [dart:ui.Image] (zero extra
/// decode cost). A single [CustomPainter.paint] call draws the whole field —
/// one compositor layer total.
///
/// GIF frame cycling is driven by a single [Ticker] with delta-time tracking.
/// Only paths whose images are already loaded participate in ticking;
/// in-flight loads simply render nothing until they complete.
class SparkleLayer extends ConsumerStatefulWidget {
  const SparkleLayer({super.key});

  @override
  ConsumerState<SparkleLayer> createState() => _SparkleLayerState();
}

class _SparkleLayerState extends ConsumerState<SparkleLayer>
    with SingleTickerProviderStateMixin {
  /// path → decoded frame (shared across all sparkles at that path)
  final Map<String, AnimatedFrame> _cache = {};

  /// Paths currently being loaded — prevents duplicate decode requests.
  final Set<String> _loading = {};

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  /// Incremented when any frame advances or a new image finishes loading.
  /// Passed to the painter so [shouldRepaint] can detect actual changes.
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  // ── Frame ticking ────────────────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    final delta = elapsed - _lastTick;
    _lastTick = elapsed;

    // Only tick paths that have a loaded image — off-screen or not-yet-loaded
    // paths accumulate no frame time and stay paused.
    for (final frame in _cache.values) {
      if (frame.tick(delta)) {
        frame.advance(() {
          if (mounted) setState(() => _version++);
        });
      }
    }
    // Note: we do NOT call setState every tick — only when a frame advances
    // or a new image loads. The painter is repainted then, not every 16 ms.
  }

  // ── Image loading ────────────────────────────────────────────────────────

  Future<void> _loadImage(String path) async {
    if (_cache.containsKey(path) || _loading.contains(path)) { return; }
    _loading.add(path);
    // Decode at display size — sparkles are small decorations; 128 px is ample.
    final frame = await AnimatedFrame.load(
      path,
      targetWidth: 128,
      targetHeight: 128,
    );
    _loading.remove(path);
    if (!mounted || frame == null) { return; }
    _cache[path] = frame;
    setState(() => _version++);
  }

  /// Remove cache entries whose paths are no longer in the active sparkle list.
  /// Called each build so memory is reclaimed promptly on theme shuffles.
  void _evictStale(Set<String> activePaths) {
    final stale = _cache.keys.where((p) => !activePaths.contains(p)).toList();
    for (final p in stale) {
      _cache.remove(p)?.dispose();
      _loading.remove(p);
    }
    if (stale.isNotEmpty) { _version++; }
  }

  void _clearCache() {
    for (final f in _cache.values) {
      f.dispose();
    }
    _cache.clear();
    _loading.clear();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clearCache();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sparkles = ref.watch(sparkleImagesProvider);
    // Quality "off" = empty list — renders nothing and lets _evictStale
    // free every cached frame on the next pass.
    if (sparkles.isEmpty && _cache.isNotEmpty) {
      _clearCache();
    }
    final size = MediaQuery.of(context).size;

    // Evict stale cache entries first, then kick off any missing loads.
    final activePaths = {for (final s in sparkles) s.path};
    _evictStale(activePaths);

    // Fire-and-forget load for any path not yet in cache.
    for (final s in sparkles) {
      _loadImage(s.path); // no-op if already cached or in-flight
    }

    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _SparkleLayerPainter(
            sparkles: sparkles,
            cache: _cache,
            screenW: size.width,
            screenH: size.height,
            version: _version,
          ),
        ),
      ),
    );
  }
}

// ── Painter ──────────────────────────────────────────────────────────────────

class _SparkleLayerPainter extends CustomPainter {
  final List<PlacedOverlay> sparkles;
  final Map<String, AnimatedFrame> cache;
  final double screenW;
  final double screenH;
  final int version;

  _SparkleLayerPainter({
    required this.sparkles,
    required this.cache,
    required this.screenW,
    required this.screenH,
    required this.version,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x66FFFFFF) // 0.4 alpha white — matches old Opacity(0.4)
      ..filterQuality = FilterQuality.low;

    for (final s in sparkles) {
      final frame = cache[s.path];
      if (frame == null) continue; // still loading — silently skip

      final img = frame.current;
      final imgW = img.width.toDouble();
      final imgH = img.height.toDouble();
      final cx = s.x * screenW;
      final cy = s.y * screenH;
      final angle = s.rotation * math.pi / 180.0;

      canvas.save();
      canvas.translate(cx + imgW / 2, cy + imgH / 2);
      if (angle != 0) canvas.rotate(angle);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, imgW, imgH),
        Rect.fromCenter(center: Offset.zero, width: imgW, height: imgH),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _SparkleLayerPainter old) =>
      old.version != version ||
      old.sparkles != sparkles ||
      old.screenW != screenW ||
      old.screenH != screenH;
}
