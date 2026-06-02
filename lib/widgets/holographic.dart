import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'render_layers.dart';

/// Shared ticker that drives every holographic overlay in the app. One
/// frame callback, many listeners — cheaper than giving each sticker its
/// own AnimationController when the Gachadex grid paints 150+ of them.
///
/// Exposes monotonic [seconds] since the first listener was added. Each
/// animation is responsible for its own timing: compute its phase as
/// `(seconds / myPeriod) % 1` for looping animations, or use seconds
/// directly for animations that don't need to wrap.
class HoloClock extends ChangeNotifier {
  static final HoloClock instance = HoloClock._();
  HoloClock._();

  /// Monotonic elapsed seconds since the first listener was added.
  double seconds = 0.0;
  bool _scheduled = false;
  int? _baseMicros;

  void _onFrame(Duration timeStamp) {
    _scheduled = false;
    if (!hasListeners) return;
    _baseMicros ??= timeStamp.inMicroseconds;
    final next = (timeStamp.inMicroseconds - _baseMicros!) / 1e6;
    if (next != seconds) {
      seconds = next;
      notifyListeners();
    }
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback(_onFrame);
    SchedulerBinding.instance.scheduleFrame();
  }

  @override
  void addListener(VoidCallback listener) {
    final wasEmpty = !hasListeners;
    super.addListener(listener);
    if (wasEmpty) _schedule();
  }
}

/// Wraps any widget with the holographic shimmer overlay. When [maskToAlpha]
/// is true the effect is clipped to the child's own alpha via a srcATop
/// blend (so the shimmer only appears where the sprite is opaque). When
/// false the effect covers the entire child rectangle.
class HoloLayer extends StatefulWidget {
  final Widget child;
  final bool maskToAlpha;
  final BorderRadius? clipRadius;
  const HoloLayer({
    super.key,
    required this.child,
    this.maskToAlpha = false,
    this.clipRadius,
  });

  @override
  State<HoloLayer> createState() => _HoloLayerState();
}

class _HoloLayerState extends State<HoloLayer> {
  @override
  void initState() {
    super.initState();
    HoloClock.instance.addListener(_onTick);
  }

  @override
  void dispose() {
    HoloClock.instance.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Blob Lissajous cycle period — fx=1 blob completes one loop in this
    // many seconds. Entirely independent of rainbow/sparkle timing.
    const blobBasePeriodSec = 240.0;
    final phase =
        (HoloClock.instance.seconds / blobBasePeriodSec) % 1.0;
    Widget overlay = IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: HoloPainter(phase: phase),
      ),
    );
    if (widget.maskToAlpha) {
      overlay = BlendMask(blendMode: BlendMode.srcATop, child: overlay);
    }
    Widget content = Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(child: overlay),
      ],
    );
    if (widget.maskToAlpha) {
      content = SaveLayer(child: content);
    }
    if (widget.clipRadius != null) {
      content = ClipRRect(
        borderRadius: widget.clipRadius!,
        clipBehavior: Clip.antiAlias,
        child: content,
      );
    }
    return content;
  }
}

/// Paints the holographic shimmer cloud — a field of color-shifting
/// Lissajous blobs. Use inside a layer that can absorb additive blending
/// (e.g. under a [BlendMask] with [BlendMode.srcATop]).
class HoloPainter extends CustomPainter {
  final double phase; // 0..1 looped from the shared clock
  HoloPainter({required this.phase});

  // Saturated hues only — pale/white-ish colors would wash to solid white
  // under additive blending with many overlaps. Keeping colors distinct is
  // what makes the cloud read as "shifting multicolored" instead of glare.
  static const _hues = <Color>[
    Color(0xFFFF3388), // hot pink
    Color(0xFFFF66AA), // pink
    Color(0xFFFF8844), // orange
    Color(0xFFFFCC33), // gold
    Color(0xFF66CC55), // green
    Color(0xFF33BBAA), // teal
    Color(0xFF4488FF), // sky blue
    Color(0xFF6644CC), // indigo
    Color(0xFFAA55DD), // violet
    Color(0xFFE060C0), // magenta
  ];

  // Per-aura path frequencies. Picked as small integer pairs so each
  // blob's Lissajous path closes cleanly at the 120 s wrap. A mix of
  // (1,N) and (N,M) pairs gives different winding shapes — some swing
  // back and forth, some trace figure-8s, some do slow loops.
  static const _freqPairs = <List<int>>[
    [1, 1], [1, 2], [2, 1], [1, 3], [3, 1],
    [2, 3], [3, 2], [1, 4], [4, 1], [2, 5], [5, 2],
    [3, 4], [4, 3],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final minSide = size.shortestSide;

    // Each aura is drawn as a cluster of overlapping ovals inside a
    // save-layer, which flattens them into a single blob at a single
    // alpha before they reach the canvas. Blobs live in a 4× field
    // centered on the widget — the portion overlapping the widget is
    // what's visible, so plenty of blobs drift near the edges at any
    // given time. The whole field additionally translates on its own
    // slow orbit so the cloud also pans in and out of the frame.
    final int count = minSide < 60 ? 32 : 160;
    // More sub-ovals per blob = more organic, less ellipsoidal silhouette.
    final int subCount = minSide < 60 ? 6 : 10;
    final int giantStart = (count * 0.80).floor();

    // Virtual field: 4× the widget in both dimensions, centered on it.
    final fieldW = size.width * 4;
    final fieldH = size.height * 4;
    final fieldOriginX = -size.width * 1.5;
    final fieldOriginY = -size.height * 1.5;

    // Field-level translation — a Lissajous (1:2) drift roughly as large
    // as the widget itself, so edge blobs wander across the frame over
    // the clock cycle rather than just rotating around the center.
    final fieldDriftX =
        math.sin(phase * 2 * math.pi * 1) * size.width * 1.0;
    final fieldDriftY =
        math.sin(phase * 2 * math.pi * 2) * size.height * 0.7;

    final subPaint = Paint();

    for (int i = 0; i < count; i++) {
      final pair = _freqPairs[i % _freqPairs.length];
      final fx = pair[0].toDouble();
      final fy = pair[1].toDouble();
      final ox = ((i * 101) % 1000) / 1000.0;
      final oy = ((i * 223) % 1000) / 1000.0;

      // Blob position in field coords, then translated into widget coords
      // (plus the global field drift).
      final tx = 2 * math.pi * (fx * phase + ox);
      final ty = 2 * math.pi * (fy * phase + oy);
      final x = (0.5 + 0.42 * math.sin(tx)) * fieldW +
          fieldOriginX +
          fieldDriftX;
      final y = (0.5 + 0.42 * math.sin(ty)) * fieldH +
          fieldOriginY +
          fieldDriftY;

      // Slow pulse — one cycle per clock period, a few blobs at 2x.
      final pulseFreq = (i % 6 == 0) ? 2.0 : 1.0;
      final pulseOff = ((i * 373) % 1000) / 1000.0;
      final pulse =
          0.5 + 0.5 * math.sin(2 * math.pi * (pulseFreq * phase + pulseOff));

      final isGiant = i >= giantStart;
      final sizeBase = isGiant
          ? minSide * (1.10 + ((i * 53) % 70) / 100.0) // 110–180%
          : minSide * (0.14 + ((i * 53) % 60) / 100.0); // 14–74%

      // Cull blobs that fall entirely outside the widget. The field is
      // 4× so most blobs are off-screen at any given moment — skipping
      // them here keeps the save-layer cost per frame in check.
      final reach = sizeBase * 1.4;
      if (x + reach < 0 ||
          x - reach > size.width ||
          y + reach < 0 ||
          y - reach > size.height) {
        continue;
      }

      final hue = _hues[i % _hues.length];
      final sizeFade = 1.0 - ((i * 53) % 60) / 200.0;
      // Small widgets (dex grid thumbnails, smattering sprites) need a
      // higher per-blob alpha — the default tuning is for big card-sized
      // surfaces where many blobs overlap. A ~2.5× bump makes the holo
      // effect actually readable at 40–60 px.
      final smallBoost = minSide < 90 ? 2.5 : 1.0;
      final layerAlpha = isGiant
          ? ((0.025 + pulse * 0.05) * sizeFade * smallBoost).clamp(0.0, 0.30)
          : ((0.06 + pulse * 0.10) * sizeFade * smallBoost).clamp(0.0, 0.45);

      final spin = (i % 3 == 0) ? 2.0 : 1.0;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(2 * math.pi * spin * phase + ox * 2 * math.pi);

      final blobBounds = Rect.fromCircle(
        center: Offset.zero,
        radius: sizeBase * 1.2,
      );
      final layerPaint = Paint()
        ..color = Color.fromRGBO(0, 0, 0, layerAlpha);
      canvas.saveLayer(blobBounds, layerPaint);

      subPaint.color = hue;
      for (int s = 0; s < subCount; s++) {
        final subSeed = i * 37 + s * 97;
        final subAng = (subSeed % 360) * math.pi / 180.0;
        final subMag = sizeBase * (((subSeed * 7) % 28) / 100.0);
        final sx = math.cos(subAng) * subMag;
        final sy = math.sin(subAng) * subMag;
        final subRx = sizeBase *
            (0.45 + ((subSeed * 3) % 40) / 100.0) *
            (0.85 + pulse * 0.25);
        final subRy = sizeBase *
            (0.30 + ((subSeed * 5) % 35) / 100.0) *
            (0.85 + pulse * 0.25);
        final subRot = ((subSeed * 11) % 360) * math.pi / 180.0;

        canvas.save();
        canvas.translate(sx, sy);
        canvas.rotate(subRot);
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset.zero, width: subRx * 2, height: subRy * 2),
          subPaint,
        );
        canvas.restore();
      }

      canvas.restore();
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant HoloPainter old) => old.phase != phase;
}
