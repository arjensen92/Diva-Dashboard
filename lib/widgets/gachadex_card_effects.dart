import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'holographic.dart';

/// Painter-backed visual effects overlaid on the gachadex card: blinking
/// star sparkles (both rectangular-fill and border-ring variants) and
/// the gradient/solid border ring. All hooked into [HoloClock] so they
/// share the app-wide animation tick.

// ===== Sparkle timing =====

/// Per-sparkle blink periods (seconds). Each one is an integer divisor
/// of the 120 s holo clock, so individual blinks close cleanly at
/// wrap-around and the overall pattern doesn't repeat at a period
/// shorter than the clock itself. The varied set kills any visible
/// synchronization between sparkles — no two neighbors blink on the
/// same schedule.
const _sparklePeriods = <double>[
  3.0, 4.0, 5.0, 6.0, 8.0, 10.0, 12.0, 15.0,
];

/// Blink visibility (0..1) for sparkle [i] at [clockSec] seconds. Each
/// sparkle picks its own period, offset, and on-duration from hashed
/// values of [i], so a grid of them blinks asynchronously.
double _sparkleVisibility(int i, double clockSec) {
  final periodSec = _sparklePeriods[i % _sparklePeriods.length];
  final offsetFrac = ((i * 317) % 1000) / 1000.0;
  // Blink length 1.0–2.5 s — slow, visible blink (not a quick flicker).
  final durationSec = 1.0 + ((i * 541) % 1000) / 1000.0 * 1.5;
  final localT = (clockSec + offsetFrac * periodSec) % periodSec;
  if (localT >= durationSec) return 0.0;
  final p = localT / durationSec;
  if (p < 0.25) return p / 0.25; // soft ramp-up
  if (p < 0.75) return 1.0; // sustain
  return (1.0 - p) / 0.25; // soft fade-out
}

/// Draws a 4-point star centered at the origin.
void _drawFourPointStar(Canvas canvas, Paint paint, double outR, double inR) {
  final star = Path();
  for (int j = 0; j < 4; j++) {
    final outAng = -math.pi / 2 + j * math.pi / 2;
    final inAng = outAng + math.pi / 4;
    final ox = math.cos(outAng) * outR;
    final oy = math.sin(outAng) * outR;
    final ix = math.cos(inAng) * inR;
    final iy = math.sin(inAng) * inR;
    if (j == 0) {
      star.moveTo(ox, oy);
    } else {
      star.lineTo(ox, oy);
    }
    star.lineTo(ix, iy);
  }
  star.close();
  canvas.drawPath(star, paint);
}

// ===== FillSparkles — rectangular sparkle field =====

/// Sparkles scattered over a rectangular area. The caller is expected
/// to clip this widget to the desired shape (e.g. wrap in [ClipRRect]
/// for the rarity chip, [ClipPath] for the banner).
class FillSparkles extends StatefulWidget {
  final int count;
  const FillSparkles({super.key, this.count = 24});

  @override
  State<FillSparkles> createState() => _FillSparklesState();
}

class _FillSparklesState extends State<FillSparkles> {
  @override
  void initState() {
    super.initState();
    HoloClock.instance.addListener(_tick);
  }

  @override
  void dispose() {
    HoloClock.instance.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _FillSparklesPainter(
        clockSec: HoloClock.instance.seconds,
        count: widget.count,
      ),
    );
  }
}

class _FillSparklesPainter extends CustomPainter {
  final double clockSec;
  final int count;
  _FillSparklesPainter({required this.clockSec, required this.count});

  @override
  void paint(Canvas canvas, Size size) {
    final sparkle = Paint()..blendMode = BlendMode.plus;
    for (int i = 0; i < count; i++) {
      final x = ((i * 127) % 1000) / 1000.0 * size.width;
      final y = ((i * 251) % 1000) / 1000.0 * size.height;
      final vis = _sparkleVisibility(i, clockSec);
      if (vis <= 0) continue;
      final outR = 2.0 + ((i * 5) % 5) / 2.0;
      final inR = outR * 0.22;
      sparkle.color = Colors.white.withValues(alpha: vis * 0.9);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(((i * 29) % 100) / 100.0 * math.pi / 2);
      _drawFourPointStar(canvas, sparkle, outR, inR);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _FillSparklesPainter old) =>
      old.clockSec != clockSec || old.count != count;
}

// ===== BorderSparkles — sparkles clipped to the ring annulus =====

/// Tiny 4-point star sparkles that blink along the border ring. The
/// painter clips to the ring path so sparkles never bleed into the card
/// interior or off the outer edge. Used on mythical cards only.
class BorderSparkles extends StatefulWidget {
  final double radius;
  final double thickness;
  const BorderSparkles({
    super.key,
    required this.radius,
    required this.thickness,
  });

  @override
  State<BorderSparkles> createState() => _BorderSparklesState();
}

class _BorderSparklesState extends State<BorderSparkles> {
  @override
  void initState() {
    super.initState();
    HoloClock.instance.addListener(_tick);
  }

  @override
  void dispose() {
    HoloClock.instance.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BorderSparklesPainter(
        clockSec: HoloClock.instance.seconds,
        radius: widget.radius,
        thickness: widget.thickness,
      ),
      size: Size.infinite,
    );
  }
}

class _BorderSparklesPainter extends CustomPainter {
  final double clockSec;
  final double radius;
  final double thickness;
  _BorderSparklesPainter({
    required this.clockSec,
    required this.radius,
    required this.thickness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Clip strictly to the border ring so a sparkle can't overflow
    // into either the card interior or off the card's outside edge.
    final outerRect = Offset.zero & size;
    final innerRect = Rect.fromLTRB(
      thickness,
      thickness,
      size.width - thickness,
      size.height - thickness,
    );
    final outerRRect =
        RRect.fromRectAndRadius(outerRect, Radius.circular(radius));
    final innerRRect = RRect.fromRectAndRadius(
      innerRect,
      Radius.circular(math.max(0, radius - thickness)),
    );
    final ring = Path()
      ..addRRect(outerRRect)
      ..addRRect(innerRRect)
      ..fillType = PathFillType.evenOdd;

    canvas.save();
    canvas.clipPath(ring);

    // Positions sampled around the center by angle; clamp to just
    // inside the outer rect so all sparkles land inside the ring
    // annulus.
    const count = 40;
    final cx = size.width / 2;
    final cy = size.height / 2;

    final sparkle = Paint()..blendMode = BlendMode.plus;

    for (int i = 0; i < count; i++) {
      // Random angle and random radial position within the ring so
      // sparkles don't sit on an obvious regular grid.
      final angle = ((i * 193) % 1000) / 1000.0 * 2 * math.pi;
      final radialFrac = ((i * 313) % 1000) / 1000.0; // 0..1 across ring width
      final c = math.cos(angle);
      final s = math.sin(angle);
      final limX = c == 0 ? double.infinity : cx / c.abs();
      final limY = s == 0 ? double.infinity : cy / s.abs();
      // Outer rectangle perimeter at this angle; pull inward between
      // `thickness*radialFrac` and `0` from the outside edge so the
      // sparkle lands anywhere across the ring's thickness.
      final scale = math.min(limX, limY) - 1.0 - thickness * radialFrac;
      final px = cx + c * scale;
      final py = cy + s * scale;

      final vis = _sparkleVisibility(i, clockSec);
      if (vis <= 0) continue;

      // Star geometry — outer radius 2.5–5 px, very sharp inner radius.
      final outR = 2.5 + ((i * 5) % 5) / 2.0;
      final inR = outR * 0.22;
      sparkle.color = Colors.white.withValues(alpha: vis * 0.95);
      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(((i * 29) % 100) / 100.0 * math.pi / 2);
      _drawFourPointStar(canvas, sparkle, outR, inR);
      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BorderSparklesPainter old) =>
      old.clockSec != clockSec ||
      old.radius != radius ||
      old.thickness != thickness;
}

// ===== BorderRing — gradient/solid ring frame =====

/// A gradient/solid frame around a rounded rectangle. Drawn as a ring
/// via an even-odd path so it overlays the card without covering the
/// interior. A null color AND null gradient means "don't draw the
/// ring" — used for mythical cards where the card-wide rainbow overlay
/// fills the ring shape separately.
class BorderRing extends StatelessWidget {
  final double radius;
  final double thickness;
  final Color? color;
  final Gradient? gradient;
  const BorderRing({
    super.key,
    required this.radius,
    required this.thickness,
    this.color,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BorderRingPainter(
        radius: radius,
        thickness: thickness,
        color: color,
        gradient: gradient,
      ),
    );
  }
}

class _BorderRingPainter extends CustomPainter {
  final double radius;
  final double thickness;
  final Color? color;
  final Gradient? gradient;
  _BorderRingPainter({
    required this.radius,
    required this.thickness,
    this.color,
    this.gradient,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (color == null && gradient == null) return;
    final outerRect = Offset.zero & size;
    final innerRect = Rect.fromLTRB(
      thickness,
      thickness,
      size.width - thickness,
      size.height - thickness,
    );
    final innerRadius = math.max(0.0, radius - thickness);
    final outerRRect =
        RRect.fromRectAndRadius(outerRect, Radius.circular(radius));
    final innerRRect =
        RRect.fromRectAndRadius(innerRect, Radius.circular(innerRadius));
    final ring = Path()
      ..addRRect(outerRRect)
      ..addRRect(innerRRect)
      ..fillType = PathFillType.evenOdd;
    final paint = Paint();
    if (gradient != null) {
      paint.shader = gradient!.createShader(outerRect);
    } else {
      paint.color = color!;
    }
    canvas.drawPath(ring, paint);
  }

  @override
  bool shouldRepaint(covariant _BorderRingPainter old) =>
      old.radius != radius ||
      old.thickness != thickness ||
      old.color != color ||
      old.gradient != gradient;
}
