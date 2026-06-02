import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../gachamon/gachamon_data.dart';
import 'sticker_sprite.dart';
import '../services/path_service.dart';
import '../services/gachamon_game_service.dart';
import '../theme/animated_backgrounds.dart';
import '../theme/app_colors.dart';

/// Picked once at app launch from the shared pastel palette — the notebook
/// page stays the same color for the whole session but varies between runs.
final Color _notebookPageColor =
    themePalette[math.Random().nextInt(themePalette.length)];

/// Path to the gachaball icon used in the notebook corners and the full-
/// screen status row. Resolved once; widgets use [File] to load.
String get _gachaballIconPath =>
    p.join(PathService.iconsDir, 'gachaball_icon.png');

/// Dashboard card for the Gachamon game — rendered as a tiny spiral-bound
/// notebook. The notebook page (pastel color from [themePalette]) fills
/// the card interior with a drop shadow, a decorative squiggle border,
/// gachaball stamps in the corners, and the smattering of caught gachamon
/// on top. A spiral binding runs along the top.
class GachamonCardContent extends ConsumerWidget {
  const GachamonCardContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gachamonGameProvider);

    // Expand duplicates — each catch (not each unique gachamon) gets a
    // sprite. Index differentiates copies so their seeded positions
    // don't land on top of each other.
    final instances = <_Instance>[];
    for (final key in game.catchOrder) {
      final count = game.caught[key] ?? 1;
      for (var i = 0; i < count; i++) {
        instances.add(_Instance(key: key, copy: i));
      }
    }
    final holoKeys = game.holo.entries
        .where((e) => e.value > 0)
        .map((e) => e.key)
        .toSet();

    return LayoutBuilder(builder: (context, constraints) {
      // Binding height = half the ring diameter + a small top pad so
      // the ring tops sit right at the card's top edge. The rings are
      // vertically centered on the page top line, so this arrangement
      // keeps half the ring in the binding area and half on the paper.
      const double _ringDiameter = 44.0;
      const double _bindingTopPad = 2.0;
      const bindingHeight = _ringDiameter / 2 + _bindingTopPad;
      const pageInset = 6.0;
      final pageRect = Rect.fromLTWH(
        pageInset,
        bindingHeight,
        constraints.maxWidth - pageInset * 2,
        constraints.maxHeight - bindingHeight - pageInset,
      );

      // Keep the smattering clear of the area where the binding rings
      // and the holes render on top of the page. The holes are centered
      // at (pageTopY + ringRadius - 4) with radius 11 — their bottom is
      // at ringRadius + 7 below pageTopY. Add a few px of breathing
      // room so sprites don't crowd the holes.
      const double _bindingOverlayBottom = _ringDiameter / 2 + 7.0;
      const double _smatteringTopReserve = _bindingOverlayBottom + 6.0;

      final pageContent = instances.isEmpty
          ? const _EmptyState()
          : _Smattering(
              instances: instances,
              size: pageRect.size,
              topReserve: _smatteringTopReserve,
              holoKeys: holoKeys,
            );

      // Decorative border color — darker tint of the page color so the
      // squiggles read as printed-on-paper doodles rather than floating.
      final hsl = HSLColor.fromColor(_notebookPageColor);
      final decorColor = hsl
          .withLightness((hsl.lightness * 0.4).clamp(0.0, 1.0))
          .withSaturation((hsl.saturation * 0.95).clamp(0.0, 1.0))
          .toColor()
          .withValues(alpha: 0.85);

      // Corner ball footprint — used both for placement and to tell the
      // squiggle painter how far to stay clear of the corners.
      const double ballInset = 6.0;
      const double ballGap = 4.0; // breathing room between squiggle end and ball
      // Directional extra padding for the corner stamps + squiggle border.
      // Top gets the big pad (binding rings descend onto the paper);
      // other sides get modest breathing room.
      const double topExtraPad = 34.0;
      const double bottomExtraPad = 8.0;
      const double sideExtraPad = 10.0;
      final ballSize = _ballSizeFor(pageRect.size);
      final cornerClearance = ballInset + ballSize + ballGap;

      // The binding painter area spans from the top of the card down a
      // bit past the page top so the left-half wire can extend onto the
      // page surface. Both back and front painters use the same rect so
      // coordinates align between them.
      final bindingRect = Rect.fromLTWH(
        pageInset,
        0,
        constraints.maxWidth - pageInset * 2,
        bindingHeight + 18,
      );

      return Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // 1) Back wire halves — painted FIRST so the page covers the
          // portion below pageTopY. Each loop's right half is drawn here.
          Positioned.fromRect(
            rect: bindingRect,
            child: CustomPaint(
              painter: _SpiralBindingPainter(
                pageTopY: bindingHeight,
                ringDiameter: _ringDiameter,
                topPad: _bindingTopPad,
                side: _WireSide.back,
              ),
            ),
          ),

          // 2) Notebook page — pastel fill with drop shadow.
          Positioned.fromRect(
            rect: pageRect,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _notebookPageColor,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 5,
                    offset: Offset(1, 3),
                  ),
                ],
              ),
              child: ClipRect(
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    // Decorative squiggle border, under everything else.
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _SquiggleBorderPainter(
                          color: decorColor,
                          cornerClearance: cornerClearance,
                          topExtraInset: topExtraPad,
                          bottomExtraInset: bottomExtraPad,
                          sideExtraInset: sideExtraPad,
                        ),
                      ),
                    ),
                    // Gachaball stamps in each corner.
                    ..._cornerGachaballs(
                      ballSize: ballSize,
                      inset: ballInset,
                      topExtra: topExtraPad,
                      bottomExtra: bottomExtraPad,
                      sideExtra: sideExtraPad,
                    ),
                    // Smattering on top.
                    Positioned.fill(child: pageContent),
                  ],
                ),
              ),
            ),
          ),

          // 3) Front wire halves — painted LAST so the left half of each
          // loop renders on top of the page surface. This sells the
          // 3D spiral illusion: left side in front of paper, right side
          // behind it.
          Positioned.fromRect(
            rect: bindingRect,
            child: CustomPaint(
              painter: _SpiralBindingPainter(
                pageTopY: bindingHeight,
                ringDiameter: _ringDiameter,
                topPad: _bindingTopPad,
                side: _WireSide.front,
              ),
            ),
          ),
        ],
      );
    });
  }

  /// Four gachaball icons, one per page corner, with directional padding
  /// so each pair (top/bottom, left/right) can have its own breathing
  /// room. Top pair's padding is the largest to clear the binding rings.
  List<Widget> _cornerGachaballs({
    required double ballSize,
    required double inset,
    required double topExtra,
    required double bottomExtra,
    required double sideExtra,
  }) {
    final ball = SizedBox(
      width: ballSize,
      height: ballSize,
      child: Opacity(
        opacity: 0.75,
        child: Image.file(
          File(_gachaballIconPath),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
    return [
      Positioned(
          left: inset + sideExtra, top: inset + topExtra, child: ball),
      Positioned(
          right: inset + sideExtra, top: inset + topExtra, child: ball),
      Positioned(
          left: inset + sideExtra, bottom: inset + bottomExtra, child: ball),
      Positioned(
          right: inset + sideExtra, bottom: inset + bottomExtra, child: ball),
    ];
  }
}

/// Corner gachaball size — ~40% of the page's short side, clamped so they
/// read as bold corner stamps on large cards but don't dominate small ones.
double _ballSizeFor(Size pageSize) {
  return (math.min(pageSize.width, pageSize.height) * 0.40)
      .clamp(40.0, 80.0);
}

class _Instance {
  final String key;
  final int copy;
  const _Instance({required this.key, required this.copy});
}

class _Smattering extends StatelessWidget {
  final List<_Instance> instances;
  final Size size;
  /// Minimum y position inside [size] for sprites — reserved area at the
  /// top of the page where the binding rings and holes render overlays.
  final double topReserve;
  final Set<String> holoKeys;
  const _Smattering({
    required this.instances,
    required this.size,
    required this.topReserve,
    required this.holoKeys,
  });

  /// Cap on how many sprites the smattering renders at once. Past this,
  /// every additional caught Gachamon stops loading another sticker sprite —
  /// memory savings scale linearly with the cap. Sprites are picked
  /// deterministically from the catch list so the same set shows on each
  /// rebuild (until the catch list itself changes).
  static const int _maxSprites = 20;

  @override
  Widget build(BuildContext context) {
    // Deterministic sample of up to [_maxSprites] from the catch list. The
    // sample seed is derived from the catch list contents, so the visible
    // set is stable until the player catches something new.
    final sample = _pickSample(instances);
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: sample.map((inst) {
        final pk = gachamonByKey(inst.key);
        if (pk == null) return const SizedBox.shrink();
        // Seed blends key + copy index so duplicates get distinct positions.
        final rng = math.Random(inst.key.hashCode ^ (inst.copy * 0x9E3779B1));
        // 70–110px per sprite — much larger now that there are at most
        // 20 of them. Rotation is a full 0..2π so sprites face every
        // direction — no two tilts look the same.
        final spriteSize = 70.0 + rng.nextDouble() * 40;
        final rotation = rng.nextDouble() * 2 * math.pi;
        final maxX = (size.width - spriteSize).clamp(0.0, double.infinity);
        final minY = topReserve;
        final maxY =
            (size.height - spriteSize).clamp(minY, double.infinity);
        final x = rng.nextDouble() * maxX;
        final y = minY + rng.nextDouble() * (maxY - minY);
        return Positioned(
          left: x,
          top: y,
          child: Transform.rotate(
            angle: rotation,
            child: SizedBox(
              width: spriteSize,
              height: spriteSize,
              child: StickerSprite(
                spritePath: gachamonSpritePath(pk),
                isHolo: holoKeys.contains(inst.key),
                outlineRadius: 3.0,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Pick up to [_maxSprites] instances from [all], seeded by the list
  /// contents so the chosen set stays stable across rebuilds. When the
  /// catch list changes the sample reshuffles; otherwise it's frozen.
  List<_Instance> _pickSample(List<_Instance> all) {
    if (all.length <= _maxSprites) return all;
    // Hash the keys+copies so the sample is content-addressed — two
    // identical catch lists produce the same sample.
    int seed = all.length;
    for (final inst in all) {
      seed = (seed * 31) ^ inst.key.hashCode ^ inst.copy;
    }
    final rng = math.Random(seed);
    final indices = List<int>.generate(all.length, (i) => i)..shuffle(rng);
    return [for (final i in indices.take(_maxSprites)) all[i]];
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.catching_pokemon, size: 36, color: Colors.red),
          SizedBox(height: 4),
          Text(
            'Tap to catch',
            style: TextStyle(
              fontFamily: 'PressStart2P',
              fontSize: 10,
              color: AppColors.textMuted,
              shadows: AppColors.textShadow,
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints a stylish wavy border around the notebook page — a sine-wave
/// squiggle inset from each of the four edges, drawn in a darker tint of
/// the page color so it reads like a printed decorative margin.
class _SquiggleBorderPainter extends CustomPainter {
  final Color color;
  /// Distance from each corner of the page to stay clear of — the squiggle
  /// on each edge starts/ends at this offset so it doesn't pass under the
  /// corner gachaball stamps.
  final double cornerClearance;
  /// Extra padding from the top edge — the binding rings descend onto the
  /// paper, so the top squiggle needs to sit well below pageTopY.
  final double topExtraInset;
  /// Extra padding from the bottom edge.
  final double bottomExtraInset;
  /// Extra padding from the left + right edges.
  final double sideExtraInset;
  const _SquiggleBorderPainter({
    required this.color,
    required this.cornerClearance,
    required this.topExtraInset,
    required this.bottomExtraInset,
    required this.sideExtraInset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double inset = 8.0; // distance from page edge to squiggle line
    const double amp = 3.5; // squiggle peak-to-center
    const double wavelength = 18.0; // px per full sine cycle
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // Horizontal (top + bottom) squiggles run between the corner clearances.
    // Corner clearances shift inward by sideExtraInset since the left/right
    // gachaballs are inset further, so the squiggle terminates short of them.
    final hStart = cornerClearance + sideExtraInset;
    final hEnd = size.width - cornerClearance - sideExtraInset;
    if (hEnd > hStart) {
      _drawHorizontalSquiggle(canvas, paint,
          y: inset + topExtraInset,
          xStart: hStart,
          xEnd: hEnd,
          amp: amp,
          wavelength: wavelength);
      _drawHorizontalSquiggle(canvas, paint,
          y: size.height - inset - bottomExtraInset,
          xStart: hStart,
          xEnd: hEnd,
          amp: amp,
          wavelength: wavelength);
    }

    // Vertical (left + right) squiggles start below the top gachaballs
    // and end above the bottom ones.
    final vStart = cornerClearance + topExtraInset;
    final vEnd = size.height - cornerClearance - bottomExtraInset;
    if (vEnd > vStart) {
      _drawVerticalSquiggle(canvas, paint,
          x: inset + sideExtraInset,
          yStart: vStart,
          yEnd: vEnd,
          amp: amp,
          wavelength: wavelength);
      _drawVerticalSquiggle(canvas, paint,
          x: size.width - inset - sideExtraInset,
          yStart: vStart,
          yEnd: vEnd,
          amp: amp,
          wavelength: wavelength);
    }
  }

  void _drawHorizontalSquiggle(
    Canvas canvas,
    Paint paint, {
    required double y,
    required double xStart,
    required double xEnd,
    required double amp,
    required double wavelength,
  }) {
    final path = Path();
    const stepPx = 1.5;
    final k = 2 * math.pi / wavelength;
    path.moveTo(xStart, y + math.sin(xStart * k) * amp);
    for (double x = xStart + stepPx; x <= xEnd; x += stepPx) {
      path.lineTo(x, y + math.sin(x * k) * amp);
    }
    canvas.drawPath(path, paint);
  }

  void _drawVerticalSquiggle(
    Canvas canvas,
    Paint paint, {
    required double x,
    required double yStart,
    required double yEnd,
    required double amp,
    required double wavelength,
  }) {
    final path = Path();
    const stepPx = 1.5;
    final k = 2 * math.pi / wavelength;
    path.moveTo(x + math.sin(yStart * k) * amp, yStart);
    for (double y = yStart + stepPx; y <= yEnd; y += stepPx) {
      path.lineTo(x + math.sin(y * k) * amp, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SquiggleBorderPainter old) =>
      old.color != color ||
      old.cornerClearance != cornerClearance ||
      old.topExtraInset != topExtraInset ||
      old.bottomExtraInset != bottomExtraInset ||
      old.sideExtraInset != sideExtraInset;
}

enum _WireSide { back, front }

/// Paints one half (left or right) of the metallic spiral-binding wire
/// loops across the top of the notebook. The pill-shaped loop is sliced
/// vertically at its center: the back painter draws the right halves
/// behind the page (so the page covers the part below pageTopY), and the
/// front painter draws the left halves on top of the page (so the lower
/// portion visibly rests on the paper surface).
///
/// Slits on the page — drawn only by the front painter so they appear on
/// top of the paper — mark where each wire punctures through.
class _SpiralBindingPainter extends CustomPainter {
  /// Y-coordinate where the notebook page starts, in this painter's space.
  final double pageTopY;
  final double ringDiameter;
  final double topPad;
  final _WireSide side;
  const _SpiralBindingPainter({
    required this.pageTopY,
    required this.ringDiameter,
    required this.topPad,
    required this.side,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Fully round rings — true circles centered vertically on pageTopY
    // so exactly half sits in the binding area and half on the paper.
    final double ringRadius = ringDiameter / 2;
    final double leftRingTop = topPad; // rings start right at the card top

    // Very tight pair spacing — centers are just 12 px apart so the two
    // rings overlap heavily in the binding area and their left-legs on
    // the paper are nearly touching, reading as one compact pair.
    const double pairInnerSpacing = 12.0;
    const double rightRingYOffset = 0.0;

    // Pair-based density — one pair per ~56 px of card width, several
    // more pairs than before.
    final pairFootprint = ringDiameter + pairInnerSpacing + 14.0;
    final int pairCount =
        (size.width / pairFootprint).round().clamp(3, 14);
    final pairStep = size.width / (pairCount + 1);

    // Solid color wire (no gradient). Both halves are dark gray so the
    // ring reads as uniformly-colored metal wire; the right side just a
    // shade darker to suggest it's in shadow behind the paper.
    final wirePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.6
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..color = side == _WireSide.front
          ? const Color(0xFF3A3A3A)
          : const Color(0xFF242424);

    // 1) Holes first (front painter only) — they sit on the paper UNDER
    // the wire halves so the left-legs of each pair visibly pass OVER
    // the hole. Positioned so the hole aligns with the bottom tips of
    // the two left-half arcs (at y = pageTopY + ringRadius), shifted a
    // few px left so it reads as sitting under the left-side descent.
    if (side == _WireSide.front) {
      const double holeRadius = 11.0;
      final double holeCenterY = pageTopY + ringRadius - 4.0;
      const double holeXShift = -12.0;
      final holeShadow = Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8);
      final holeFill = Paint()..color = const Color(0xDD000000);
      for (int p = 0; p < pairCount; p++) {
        final pairCx = pairStep * (p + 1);
        final holeCenter = Offset(pairCx + holeXShift, holeCenterY);
        canvas.drawCircle(holeCenter, holeRadius + 0.6, holeShadow);
        canvas.drawCircle(holeCenter, holeRadius, holeFill);
      }
    }

    // 2) Wire halves on top. Right ring is drawn AFTER left so it sits
    // on top in z-order, and is nudged upward so it visually rests just
    // above the left ring (spiral coil illusion).
    for (int p = 0; p < pairCount; p++) {
      final pairCx = pairStep * (p + 1);
      final rings = <List<double>>[
        [pairCx - pairInnerSpacing / 2, leftRingTop],
        [pairCx + pairInnerSpacing / 2, leftRingTop + rightRingYOffset],
      ];
      for (final r in rings) {
        final cx = r[0];
        final ringTop = r[1];
        final loopRect = Rect.fromLTRB(
          cx - ringRadius,
          ringTop,
          cx + ringRadius,
          ringTop + ringDiameter,
        );
        final loopRRect = RRect.fromRectAndRadius(
          loopRect,
          Radius.circular(ringRadius),
        );
        canvas.save();
        if (side == _WireSide.back) {
          canvas.clipRect(Rect.fromLTRB(cx, 0, size.width, pageTopY));
        } else {
          canvas.clipRect(Rect.fromLTRB(0, 0, cx, size.height));
        }
        canvas.drawRRect(loopRRect, wirePaint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SpiralBindingPainter old) =>
      old.pageTopY != pageTopY ||
      old.ringDiameter != ringDiameter ||
      old.topPad != topPad ||
      old.side != side;
}
