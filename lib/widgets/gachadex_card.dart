import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../gachamon/gachamon_data.dart';
import '../services/path_service.dart';
import '../services/gachamon_game_service.dart';
import 'holographic.dart';
import 'gachadex_card_effects.dart';
import 'win95.dart';

/// Reserved height for the dex-entry text slot. ~6 lines at the natural
/// fontSize 7 / line-height 1.6 (≈ 67 px). Sized to fit the longer end
/// of the typical entry range without FittedBox having to shrink the
/// text — most flavor text is 4-6 lines and renders at natural size.
/// Very long 7+ line entries shrink slightly via FittedBox.scaleDown;
/// short 1-3 line entries are vertically centered within the slot
/// (alignment: centerLeft) so the leftover space distributes evenly
/// above and below the text rather than dumping all of it at the
/// bottom. The fixed height keeps every card at the same total height
/// regardless of flavor-text length.
const double _dexEntrySlotHeight = 70.0;

/// The gachadex card display — sprite in a sunken frame, name, type icons,
/// evolution stack, dex entry, rarity chip, and the rarity-tier border. Used
/// as the caught-reveal inside the catching dialog and as the standalone
/// gachadex card modal. Pass [isHolo] to play the holographic shimmer on top
/// (orthogonal to rarity-based holographic *borders*).
class GachadexCard extends StatefulWidget {
  final Gachamon gachamon;
  final int catchCount;
  final bool isHolo;
  const GachadexCard({
    super.key,
    required this.gachamon,
    required this.catchCount,
    this.isHolo = false,
  });

  /// Every image path a [GachadexCard] for [pk] will paint. Useful for
  /// callers that want to precache before mounting the card so the card
  /// renders fully on first build (no SizedBox placeholder flash).
  static Set<String> imagePathsFor(Gachamon pk) {
    final paths = <String>{
      gachamonSpritePath(pk),
      _cardTexturePath(),
      if (pk.type1 != null)
        p.join(PathService.iconsDir, 'types',
            '${pk.type1!.toLowerCase()}.png'),
      if (pk.type2 != null)
        p.join(PathService.iconsDir, 'types',
            '${pk.type2!.toLowerCase()}.png'),
    };
    if (pk.preEvolution != null) {
      final pre = gachamonByKey(pk.preEvolution!);
      if (pre != null) paths.add(gachamonSpritePath(pre));
    }
    for (final evoKey in pk.evolution) {
      final evo = gachamonByKey(evoKey);
      if (evo != null) paths.add(gachamonSpritePath(evo));
    }
    return paths;
  }

  /// True if every image needed for [pk] is currently in
  /// PaintingBinding.imageCache. Lets the card skip its async precache
  /// pass when the parent (e.g. the catch dialog) has already warmed
  /// the cache before mounting.
  static bool allImagesCached(Gachamon pk) {
    final cache = PaintingBinding.instance.imageCache;
    for (final path in imagePathsFor(pk)) {
      if (!cache.containsKey(FileImage(File(path)))) return false;
    }
    return true;
  }

  /// Awaits a precache for every image needed by [pk]. Errors swallowed
  /// — the card's per-image errorBuilder handles missing files at paint
  /// time. Use this from a caller that wants to mount the card with all
  /// bytes already in the cache (e.g. the catch dialog before swapping
  /// _lastCaught, so the new card composites in one atomic frame).
  static Future<void> precacheImagesFor(
      BuildContext context, Gachamon pk) async {
    final paths = imagePathsFor(pk);
    await Future.wait(paths.map((path) async {
      try {
        if (!context.mounted) return;
        await precacheImage(FileImage(File(path)), context);
      } catch (_) {/* swallow */}
    }));
  }

  @override
  State<GachadexCard> createState() => _GachadexCardState();
}

class _GachadexCardState extends State<GachadexCard> {
  bool get _needsClock => widget.gachamon.rarity == GachamonRarity.mythical;

  // Used to measure the card's actual rendered dimensions after layout so
  // the mythical rainbow's gradient math can use the real bottom edge
  // instead of a hardcoded guess. Chip is measured separately so the chip
  // seam can be aligned to pixel precision regardless of the rarity
  // label's glyph metrics.
  final GlobalKey _cardKey = GlobalKey();
  final GlobalKey _chipKey = GlobalKey();
  double _measuredCardHeight = 620.0;
  double _measuredChipHeight = 26.0;

  /// Set true once all images this card renders (sprite, type icons, card
  /// texture, evolution chain sprites) are decoded and in
  /// PaintingBinding.imageCache. Until then [build] returns a fixed-size
  /// placeholder so the card never appears with pieces missing — the user
  /// sees blank space, then the fully-rendered card snaps in atomically.
  bool _imagesReady = false;

  void _measureLayout() {
    if (!mounted) return;
    bool changed = false;
    double nextCardH = _measuredCardHeight;
    double nextChipH = _measuredChipHeight;
    final cardCtx = _cardKey.currentContext;
    if (cardCtx != null) {
      final ro = cardCtx.findRenderObject();
      if (ro is RenderBox && ro.hasSize) {
        final h = ro.size.height;
        if ((h - nextCardH).abs() > 0.5) {
          nextCardH = h;
          changed = true;
        }
      }
    }
    final chipCtx = _chipKey.currentContext;
    if (chipCtx != null) {
      final ro = chipCtx.findRenderObject();
      if (ro is RenderBox && ro.hasSize) {
        final h = ro.size.height;
        if ((h - nextChipH).abs() > 0.5) {
          nextChipH = h;
          changed = true;
        }
      }
    }
    if (changed) {
      setState(() {
        _measuredCardHeight = nextCardH;
        _measuredChipHeight = nextChipH;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    if (_needsClock) HoloClock.instance.addListener(_onTick);
    // Fast path: if every image is already in imageCache (parent did the
    // precache), start ready and render fully on first build — no
    // SizedBox placeholder flash.
    if (GachadexCard.allImagesCached(widget.gachamon)) {
      _imagesReady = true;
      return;
    }
    // Slow path: parent didn't precache. Schedule async precache; until
    // it completes [build] returns the placeholder.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _precacheAllImages();
    });
  }

  /// Pre-decodes every image this card will paint into Flutter's shared
  /// imageCache before flipping [_imagesReady]. Avoids the visible
  /// piece-by-piece fade-in (sprite first, then type icons, then card
  /// texture, then evolution circles) — instead the whole card composites
  /// in one frame once all bytes are warm.
  Future<void> _precacheAllImages() async {
    await GachadexCard.precacheImagesFor(context, widget.gachamon);
    if (mounted) setState(() => _imagesReady = true);
  }

  @override
  void didUpdateWidget(covariant GachadexCard old) {
    super.didUpdateWidget(old);
    final was = old.gachamon.rarity == GachamonRarity.mythical;
    if (was != _needsClock) {
      if (was) HoloClock.instance.removeListener(_onTick);
      if (_needsClock) HoloClock.instance.addListener(_onTick);
    }
    // When the gachamon changes (e.g. catch dialog swaps _lastCaught),
    // re-evaluate readiness. The catch dialog precaches before the swap
    // so this path will normally see allImagesCached=true and stay ready
    // — meaning the new card composites in the same frame as the swap,
    // without ever showing the placeholder.
    if (old.gachamon.uniqueKey != widget.gachamon.uniqueKey) {
      if (GachadexCard.allImagesCached(widget.gachamon)) {
        if (!_imagesReady) _imagesReady = true;
      } else {
        _imagesReady = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _precacheAllImages();
        });
      }
    }
  }

  @override
  void dispose() {
    if (_needsClock) HoloClock.instance.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  Gachamon get gachamon => widget.gachamon;
  bool get isHolo => widget.isHolo;

  @override
  Widget build(BuildContext context) {
    // Hold the dialog space empty while images decode in the background.
    // Once [_precacheAllImages] completes, _imagesReady flips and the
    // full card composites in one atomic frame — no piece-by-piece pop-in.
    if (!_imagesReady) {
      return SizedBox(width: 352, height: _measuredCardHeight);
    }

    // Rainbow completes one full rotation per this many seconds. Entirely
    // independent of other animations' speeds — the clock just emits a
    // monotonic second count.
    const rainbowPeriodSec = 30.0;
    final phase = _needsClock
        ? (HoloClock.instance.seconds / rainbowPeriodSec) % 1.0
        : 0.0;
    const spriteBox = 260.0;
    const typeIconSize = 100.0;
    const nameFontSize = 14.0;

    // For `"Gachamon (Form)"` the base name shows in the top-left and the
    // form label shows centered under the sprite frame.
    String nameMain = gachamon.name;
    String? formLabel;
    final parenIdx = gachamon.name.indexOf(' (');
    if (parenIdx > 0 && gachamon.name.endsWith(')')) {
      nameMain = gachamon.name.substring(0, parenIdx);
      final extracted =
          gachamon.name.substring(parenIdx + 2, gachamon.name.length - 1);
      // "(Male)" / "(Female)" are gender variants of the same species
      // (e.g. Basculegion) — strip them from the display name but don't
      // surface them as a form label. Nidoran ♀/♂ use symbols, not parens,
      // so they aren't caught here and display as-is.
      if (extracted != 'Male' && extracted != 'Female') {
        formLabel = extracted;
      }
    }
    final rarityName = gachamon.rarity.name;
    // Sprite frame: type-colored background (ombre for dual-type), tamped
    // down by a semi-transparent white layer so the sprite stays readable.
    final baseSpriteFrame = Container(
      width: spriteBox,
      height: spriteBox,
      decoration: _typeBackground(gachamon).copyWith(
        border: Win95.sunkenBorder(width: 1.5),
      ),
      child: Container(
        // Muting layer — tune alpha here to taste.
        color: Colors.white.withValues(alpha: 0.55),
        padding: const EdgeInsets.all(10),
        child: Image.file(
          File(gachamonSpritePath(gachamon)),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.catching_pokemon, size: 60, color: Colors.red),
        ),
      ),
    );
    // Wrap the beveled sprite frame in a second sharp-cornered rectangle of
    // the card's rarity color, matching the outer border. The whole block
    // gets a drop shadow so the image sits above the card.
    final isMythical = gachamon.rarity == GachamonRarity.mythical;
    // Card width matches the Dialog's inner content area (ConstrainedBox
    // 380 minus 14 padding each side). Card height varies per-gachamon
    // based on dex-entry length — _measuredCardHeight is filled in by a
    // post-frame callback after the first layout pass, so on first frame
    // we use the previous value (or the 620 default) and then the chip
    // seam auto-corrects on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureLayout());
    const cardWidth = 352.0;
    final cardHeight = _measuredCardHeight;
    const kBorderThickness = 8.0; // local alias (borderThickness defined below)
    const kNameHeight = 22.0; // PressStart2P 14 approx height
    const kSpriteFrameSize = 272.0; // 260 sprite + 2*6 frame thickness
    const kSpriteFrameTop = kBorderThickness + 16 + kNameHeight + 10; // 56
    final kSpriteFrameLeft = (cardWidth - kSpriteFrameSize) / 2;
    const kBannerHeight = 21.0;
    const kBannerWidth = cardWidth - 2 * kBorderThickness - 6;
    const kBannerLeft = (cardWidth - kBannerWidth) / 2;
    const kBannerTop = kSpriteFrameTop + kSpriteFrameSize + 8;
    final kChipWidth = rarityName.length * 11.0 + 28.0;
    final kChipLeft = cardWidth - 2 - kChipWidth;
    // Chip height is measured after first frame via _chipKey, so the
    // gradient's chipTop matches the chip's actual paint-time position
    // to the pixel regardless of font metrics or content.
    final kChipTop = cardHeight - 2 - _measuredChipHeight;

    Gradient mythicalAt(Offset offsetInCard) => _mythicalRainbowForElement(
          cardWidth: cardWidth,
          cardHeight: cardHeight,
          phase: phase,
          elementOffsetInCard: offsetInCard,
        );

    // Rainbow gradient for gradient-tier cards.
    final spriteFrameGradient = isMythical
        ? mythicalAt(Offset(kSpriteFrameLeft, kSpriteFrameTop))
        : _rarityBorderGradient(gachamon.rarity, phase);
    // Banner and border ring both want the same card-wide rainbow for
    // mythical, but at different positions — so they read as continuous.
    final bannerGradient = isMythical
        ? mythicalAt(Offset(kBannerLeft, kBannerTop))
        : spriteFrameGradient;
    final borderRingGradient = isMythical
        ? mythicalAt(Offset.zero)
        : spriteFrameGradient;
    Widget spriteFrame = Container(
      decoration: BoxDecoration(
        color: spriteFrameGradient == null
            ? (_rarityBorderColors[gachamon.rarity] ?? Colors.white)
            : null,
        gradient: spriteFrameGradient,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(6),
      child: baseSpriteFrame,
    );
    if (isMythical) {
      spriteFrame = Stack(
        children: [
          spriteFrame,
          const Positioned.fill(
            child: IgnorePointer(
              child: BorderSparkles(radius: 0, thickness: 6),
            ),
          ),
        ],
      );
    }

    final typeRow = gachamon.type1 == null
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TypeIcon(type: gachamon.type1!, size: typeIconSize),
              if (gachamon.type2 != null)
                // Pull the second icon leftward to eat up the built-in
                // transparent padding in both icon PNGs, leaving a small
                // ~2 px visible gap between the rendered shapes.
                Transform.translate(
                  offset: const Offset(-8, 0),
                  child: _TypeIcon(type: gachamon.type2!, size: typeIconSize),
                ),
            ],
          );

    // ---- Gachadex card layout ----
    // Name in top-left above sprite, sprite centered, types below, and a
    // small pixel-font dex entry at the bottom (if we have one).
    final cardInner = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: _NameTitle(name: nameMain, fontSize: nameFontSize),
        ),
        const SizedBox(height: 10),
        Center(child: spriteFrame),
        const SizedBox(height: 8),
        // Banner stretches almost edge-to-edge — tails sit just inside the
        // card's rarity border.
        Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bw = constraints.maxWidth - 6;
              const bh = 21.0;
              const notch = 14.0;
              // Banner text lives in its own widget so we can paint it
              // above the sparkles on mythical cards (otherwise the
              // sparkles would overlay the category/H/W text).
              final bannerText = Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          gachamon.category ?? '',
                          style: const TextStyle(
                            fontFamily: 'PressStart2P',
                            fontSize: 7,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                    if (gachamon.height != null)
                      _KernedHeight(height: gachamon.height!),
                    if (gachamon.height != null && gachamon.weight != null)
                      const SizedBox(width: 10),
                    if (gachamon.weight != null)
                      Text(
                        'W: ${gachamon.weight}',
                        style: const TextStyle(
                          fontFamily: 'PressStart2P',
                          fontSize: 7,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                      ),
                  ],
                ),
              );
              if (!isMythical) {
                return _SwallowtailBanner(
                  width: bw,
                  height: bh,
                  notch: notch,
                  color: bannerGradient == null
                      ? (_rarityBorderColors[gachamon.rarity] ?? Colors.white)
                      : null,
                  gradient: bannerGradient,
                  child: bannerText,
                );
              }
              // Mythical: Stack so we can layer banner shape, then sparkles,
              // then the text on top.
              return SizedBox(
                width: bw,
                height: bh,
                child: Stack(
                  children: [
                    // Shape + gradient fill (no text — added above sparkles).
                    _SwallowtailBanner(
                      width: bw,
                      height: bh,
                      notch: notch,
                      gradient: bannerGradient,
                    ),
                    // Sparkles clipped to the swallowtail shape.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ClipPath(
                          clipper: const _SwallowtailClipper(notch: notch),
                          child: const FillSparkles(count: 14),
                        ),
                      ),
                    ),
                    // Text on top of the sparkles.
                    Positioned.fill(
                      child: IgnorePointer(child: Center(child: bannerText)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (formLabel != null) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              formLabel,
              style: const TextStyle(
                fontFamily: 'PressStart2P',
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        // Type icons live in a floating Positioned row below — they stay
        // pinned so their placement doesn't shift with the dex entry length.
        if (gachamon.dexEntry != null) ...[
          const SizedBox(height: 12),
          // Fixed-height slot. The dex entry text auto-shrinks via
          // FittedBox(scaleDown) when it would otherwise overflow this
          // box — same pattern used by the species category banner above.
          // Shorter entries render at the natural fontSize 7 and leave
          // empty space below; longer entries are uniformly scaled down
          // until they fit. Net effect: every gachadex card lands at the
          // same total height regardless of how chatty the flavor text is.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: SizedBox(
              height: _dexEntrySlotHeight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  // Card width 352 minus 18 px padding on each side.
                  width: 316,
                  child: Text(
                    gachamon.dexEntry!,
                    style: const TextStyle(
                      fontFamily: 'PressStart2P',
                      fontSize: 7,
                      height: 1.6,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );

    // Thick rarity-colored border (solid for most tiers, holographic for
    // legendary / mythical). Painted as a ring overlay (below) so chips
    // sitting at the card's edge can tuck under it.
    final borderColor = _rarityBorderColors[gachamon.rarity] ?? Colors.white;
    const borderThickness = 8.0;
    const outerRadius = 26.0;

    // The rarity chip — mythical uses a narrow pink-slice gradient that
    // matches the border's end-of-rainbow so the chip reads as part of the
    // frame. Other tiers stay solid.
    final chipGradient = isMythical
        ? mythicalAt(Offset(kChipLeft, kChipTop))
        : _rarityChipGradient(gachamon.rarity, phase);
    const chipShape = BorderRadius.only(
      topLeft: Radius.circular(14),
      bottomRight: Radius.circular(outerRadius),
    );
    const chipPadding = EdgeInsets.fromLTRB(14, 7, 14, 7);
    const chipTextStyle = TextStyle(
      fontFamily: 'PressStart2P',
      fontSize: 9,
      fontWeight: FontWeight.w700,
      color: Colors.black87,
      letterSpacing: 1,
    );
    Widget rarityCornerChip;
    if (!isMythical) {
      rarityCornerChip = Container(
        padding: chipPadding,
        decoration: BoxDecoration(
          color: chipGradient == null ? borderColor : null,
          gradient: chipGradient,
          borderRadius: chipShape,
        ),
        child: Text(rarityName.toUpperCase(), style: chipTextStyle),
      );
    } else {
      // Mythical: stack shape → sparkles → text so "MYTHICAL" reads
      // clearly above the twinkles. The sizing Container holds an
      // invisible copy of the label so the stack still sizes from text.
      rarityCornerChip = Stack(
        key: _chipKey,
        children: [
          Container(
            padding: chipPadding,
            decoration: BoxDecoration(
              gradient: chipGradient,
              borderRadius: chipShape,
            ),
            child: Text(
              rarityName.toUpperCase(),
              style:
                  chipTextStyle.copyWith(color: const Color(0x00000000)),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: chipShape,
                child: const FillSparkles(count: 12),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Padding(
                padding: chipPadding,
                child:
                    Text(rarityName.toUpperCase(), style: chipTextStyle),
              ),
            ),
          ),
        ],
      );
    }

    // Dex number — just floating text in the bottom-left, no chip/box.
    final dexNumberText = Text(
      '# ${gachamon.id}',
      style: const TextStyle(
        fontFamily: 'PressStart2P',
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
    );

    // Card is laid out as [shadow + type-bg face] then the overlayed chips
    // (dex number, rarity chip, evolution circles, types), and finally the
    // rarity-colored ring frame drawn LAST so the rarity chip's corner
    // tucks under it at the bottom-right.
    final cardStack = Stack(
      key: _cardKey,
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(outerRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(outerRadius),
            // Watercolor texture as the bottom of a Stack, with the
            // original tinted-Container-as-card-body on top. The original
            // Container keeps its typeBackgroundTint decoration + padding
            // + cardInner child untouched — so the constraint chain is
            // identical to the non-textured layout (no more broken
            // LayoutBuilder / missing banner+dex content).
            child: Stack(
              children: [
                // Solid type-color base layer. Always present so the card
                // reads as fully type-colored even when card_texture.png
                // is missing (the public stripped distribution doesn't
                // ship it). Without this base, the 0.55-alpha tint a few
                // layers up sits over the Stack's transparent background
                // and the card washes out to a pale gray.
                Positioned.fill(
                  child: DecoratedBox(decoration: _typeBackground(gachamon)),
                ),
                // Watercolor texture overlay. Optional — silently skipped
                // when the file isn't present; the solid base above keeps
                // the card looking right either way.
                Positioned.fill(
                  child: Image.file(
                    File(_cardTexturePath()),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                // Original card body — the non-Positioned sizer so the
                // Stack shrink-wraps to the card's natural height.
                Container(
                  decoration: _typeBackgroundTint(gachamon).copyWith(
                    borderRadius: BorderRadius.circular(outerRadius),
                  ),
                  padding: const EdgeInsets.fromLTRB(
                      borderThickness,
                      16 + borderThickness,
                      borderThickness,
                      117 + borderThickness),
                  child: cardInner,
                ),
              ],
            ),
          ),
        ),
        // Type icons pinned at the bottom center — position fixed regardless
        // of the dex entry length above.
        if (typeRow != null)
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(child: typeRow),
          ),
        // Dex number floats in the bottom-left, slightly out of the corner.
        Positioned(
          bottom: 11,
          left: borderThickness + 7,
          child: dexNumberText,
        ),
        // Rarity chip — flush with the card's bottom-right corner, nudged
        // 2px in so its inner edges visually merge into the border.
        Positioned(
          bottom: 2,
          right: 2,
          child: rarityCornerChip,
        ),
        // Evolution badges — top-right of the card. Pre-evo sits shifted
        // upward with its stage label below; evolutions sit lower with a
        // single stage label above them. Circles straddle the sprite top.
        Positioned(
          top: 10,
          right: 16,
          child: _EvolutionBadges(
            gachamon: gachamon,
            ringColor: spriteFrameGradient == null ? borderColor : null,
            ringGradient: spriteFrameGradient,
          ),
        ),
        // Rarity ring — drawn LAST so chips at the edge (rarity chip in the
        // bottom-right especially) tuck under the border instead of riding
        // on top of it. For mythical this ring shares the card-wide rainbow
        // with the other rarity surfaces so colors line up across seams.
        Positioned.fill(
          child: IgnorePointer(
            child: BorderRing(
              radius: outerRadius,
              thickness: borderThickness,
              color: borderRingGradient == null ? borderColor : null,
              gradient: borderRingGradient,
            ),
          ),
        ),
        // Mythical — add twinkling 4-point stars on top of the border.
        if (gachamon.rarity == GachamonRarity.mythical)
          const Positioned.fill(
            child: IgnorePointer(
              child: BorderSparkles(
                radius: outerRadius,
                thickness: borderThickness,
              ),
            ),
          ),
      ],
    );
    if (!isHolo) return cardStack;
    // Holographic catches get the shimmer over the entire card face, clipped
    // to the outer rounded corners.
    return HoloLayer(
      clipRadius: BorderRadius.circular(outerRadius),
      child: cardStack,
    );
  }
}

/// Standalone dialog wrapping [GachadexCard] for viewing a gachamon from the
/// Gachadex grid. Same visual card as the catch reveal, minus the "New Catch!"
/// badges.
void showGachadexCard(BuildContext context, Gachamon gachamon, int catchCount,
    {bool isHolo = false}) {
  showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      backgroundColor: Win95.gray,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      insetPadding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Win95Panel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Win95TitleBar(
                title: '#${gachamon.id.toString().padLeft(4, '0')}  ${gachamon.name}',
                titleFontSize: 14,
                buttonSize: 22,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                leading: const Icon(Icons.menu_book,
                    size: 16, color: Colors.white),
                onClose: () => Navigator.of(ctx).pop(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: GachadexCard(
                  gachamon: gachamon,
                  catchCount: catchCount,
                  isHolo: isHolo,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// =====================================================================
// Card interior helpers — evolution stack, info banner, type icons, text
// =====================================================================

/// Evolution stack shown in the top-right of the gachadex card.
///   - Pre-evolution circle (if any) sits shifted up with its "Stage N"
///     label below it.
///   - Evolution circle(s) (if any) sit lower with a single "Stage N" label
///     centered above them.
/// Each circle's outline is the current gachamon's rarity color; the fill is
/// the target evolution's own type-1 color, muted by a semi-transparent
/// white layer. Circles separate with a small gap so each is fully visible.
class _EvolutionBadges extends StatelessWidget {
  final Gachamon gachamon;
  final Color? ringColor;
  final Gradient? ringGradient;
  const _EvolutionBadges({
    required this.gachamon,
    this.ringColor,
    this.ringGradient,
  });

  int _stage(Gachamon pk) {
    int stage = 1;
    String? preKey = pk.preEvolution;
    int safety = 4;
    while (preKey != null && safety > 0) {
      stage++;
      final prev = gachamonByKey(preKey);
      if (prev == null || prev.preEvolution == preKey) break;
      preKey = prev.preEvolution;
      safety--;
    }
    return stage.clamp(1, 3);
  }

  Widget _circle(Gachamon target) {
    final fill = typeColors[target.type1] ?? Colors.white;
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ringGradient == null ? (ringColor ?? Colors.white) : null,
        gradient: ringGradient,
      ),
      padding: const EdgeInsets.all(2),
      child: Container(
        decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.55),
          ),
          padding: const EdgeInsets.all(2),
          child: ClipOval(
            child: Image.file(
              File(gachamonSpritePath(target)),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pre = gachamon.preEvolution != null
        ? gachamonByKey(gachamon.preEvolution!)
        : null;
    final evos = gachamon.evolution
        .map(gachamonByKey)
        .whereType<Gachamon>()
        .toList();
    if (pre == null && evos.isEmpty) return const SizedBox.shrink();

    final currentStage = _stage(gachamon);
    const labelStyle = TextStyle(
      fontFamily: 'PressStart2P',
      fontSize: 9,
      color: Colors.black87,
    );

    // Label paints on top of the circle/sprite image. In a Column, later
    // children paint over earlier ones — so pre-column keeps circle-then-
    // label order. The evo column flips that with a Stack so the label
    // (added last) sits in front of the circles.
    Widget? preColumn;
    if (pre != null) {
      preColumn = Transform.translate(
        offset: const Offset(0, -1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            _circle(pre),
            Transform.translate(
              offset: const Offset(0, -13),
              child: Text('Stage ${_stage(pre)}',
                  style: labelStyle),
            ),
          ],
        ),
      );
    }

    Widget? evoColumn;
    if (evos.isNotEmpty) {
      const gap = 6.0;
      // Non-Eevee lines: up to 5 per row; overflow goes into a second row
      // centered below.
      const maxPerRow = 5;
      Widget rowOf(List<Gachamon> mons) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < mons.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                _circle(mons[i]),
              ],
            ],
          );

      Widget circlesStack;
      if (gachamon.id == 133 && evos.length == 8) {
        // Eevee — 4 per row, overlapping. Bottom row nudged right. Explicit
        // paint order (back-to-front): sylveon, espeon, glaceon, flareon,
        // leafeon, jolteon, umbreon, vaporeon. Bottom-row ids start each
        // pair so a bottom circle tucks behind the next top circle.
        const topIds = [134, 135, 136, 196]; // Vap, Jol, Fla, Esp
        const bottomIds = [197, 470, 471, 700]; // Umb, Lea, Gla, Syl
        const zBackToFront = [700, 196, 471, 136, 470, 135, 197, 134];
        const circleSize = 58.0;
        const pitch = 46.0; // horizontal center-to-center spacing
        const rowPitch = 36.0; // vertical offset to bottom row
        const bottomRowShift = 23.0; // half a pitch → honeycomb stagger
        const topGutter = 2.0; // leaves room for the "Stage N" label
        final byId = {for (final e in evos) e.id: e};
        final children = <Widget>[];
        for (final id in zBackToFront) {
          final pk = byId[id];
          if (pk == null) continue;
          final inTop = topIds.contains(id);
          final idx = inTop ? topIds.indexOf(id) : bottomIds.indexOf(id);
          children.add(Positioned(
            left: idx * pitch + (inTop ? 0 : bottomRowShift),
            top: topGutter + (inTop ? 0 : rowPitch),
            child: _circle(pk),
          ));
        }
        final totalW =
            (topIds.length - 1) * pitch + circleSize + bottomRowShift;
        final totalH = topGutter + rowPitch + circleSize;
        circlesStack = SizedBox(
          width: totalW,
          height: totalH,
          child: Stack(clipBehavior: Clip.none, children: children),
        );
      } else {
        final rows = <Widget>[];
        if (evos.length <= maxPerRow) {
          rows.add(rowOf(evos));
        } else {
          rows.add(rowOf(evos.sublist(0, maxPerRow)));
          rows.add(const SizedBox(height: gap));
          rows.add(rowOf(evos.sublist(maxPerRow)));
        }
        // Top gutter leaves room for the label so it sits above (and slightly
        // on top of) the first row of circles.
        circlesStack = Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [const SizedBox(height: 2), ...rows],
        );
      }
      evoColumn = Transform.translate(
        offset: const Offset(0, 9),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            circlesStack,
            Positioned(
              top: 0,
              child: Text('Stage ${(currentStage + 1).clamp(1, 3)}',
                  style: labelStyle),
            ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (preColumn != null) preColumn,
        if (evoColumn != null) evoColumn,
      ],
    );
  }
}

/// A ribbon-style banner with swallowtail notches cut into each short end.
/// Uses the gachamon's rarity color (or holographic gradient). Sized to match
/// the sprite box width.
class _SwallowtailBanner extends StatelessWidget {
  final double width;
  final double height;
  final Color? color;
  final Gradient? gradient;
  final double notch;
  final Widget? child;
  const _SwallowtailBanner({
    required this.width,
    required this.height,
    this.color,
    this.gradient,
    this.notch = 14,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SwallowtailBannerPainter(
          color: color,
          gradient: gradient,
          notch: notch,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _SwallowtailBannerPainter extends CustomPainter {
  final Color? color;
  final Gradient? gradient;
  final double notch;
  _SwallowtailBannerPainter({
    this.color,
    this.gradient,
    required this.notch,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width - notch, size.height / 2)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..lineTo(notch, size.height / 2)
      ..close();
    // Drop shadow beneath the banner path.
    canvas.drawShadow(path, Colors.black, 2.5, false);
    // When both fills are null, skip the fill (shadow still renders) —
    // used for mythical cards where the rainbow overlay fills the shape.
    if (color == null && gradient == null) return;
    final paint = Paint();
    if (gradient != null) {
      paint.shader = gradient!
          .createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    } else {
      paint.color = color!;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SwallowtailBannerPainter old) =>
      old.color != color || old.gradient != gradient || old.notch != notch;
}

/// Swallowtail banner clip — mirrors the path built by
/// [_SwallowtailBannerPainter] so a sparkle overlay can be clipped to
/// exactly the same shape.
class _SwallowtailClipper extends CustomClipper<Path> {
  final double notch;
  const _SwallowtailClipper({required this.notch});

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width - notch, size.height / 2)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..lineTo(notch, size.height / 2)
      ..close();
  }

  @override
  bool shouldReclip(covariant _SwallowtailClipper old) => old.notch != notch;
}

/// Renders the icon for a Gachamon type. Filenames in `assets/icons/types/`
/// are all lowercase (e.g. `grass.png`), so we normalize the type string.
class _TypeIcon extends StatelessWidget {
  final String type;
  final double size;
  const _TypeIcon({required this.type, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final path =
        p.join(PathService.iconsDir, 'types', '${type.toLowerCase()}.png');
    return SizedBox(
      height: size,
      child: Image.file(
        File(path),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
}

/// Renders the card's height field (e.g. `2'4''`) with tightened letter
/// spacing applied only to the double apostrophes (the inch marks), so
/// the two tick characters sit closer together without affecting the
/// rest of the string.
class _KernedHeight extends StatelessWidget {
  final String height;
  const _KernedHeight({required this.height});

  @override
  Widget build(BuildContext context) {
    const baseStyle = TextStyle(
      fontFamily: 'PressStart2P',
      fontSize: 7,
      color: Colors.black87,
    );
    // letterSpacing on the first apostrophe of the pair shrinks the gap
    // to the second apostrophe. We don't touch any other characters.
    const tightBetween = TextStyle(
      fontFamily: 'PressStart2P',
      fontSize: 7,
      color: Colors.black87,
      letterSpacing: -2.5,
    );
    final idx = height.lastIndexOf("''");
    if (idx < 0) {
      return Text('H: $height', style: baseStyle, maxLines: 1);
    }
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: 'H: ${height.substring(0, idx)}'),
          const TextSpan(text: "'", style: tightBetween),
          const TextSpan(text: "'"),
        ],
      ),
      maxLines: 1,
    );
  }
}

// =====================================================================
// Rarity tier colors, gradients, and type-background decorations
// =====================================================================

/// Card-border color per rarity. Legendary and mythical tiers use gradients
/// instead (see [_rarityBorderGradient]).
const _rarityBorderColors = <GachamonRarity, Color>{
  GachamonRarity.common: Color(0xFFFFFFFF),
  GachamonRarity.uncommon: Color(0xFFCD7F32), // bronze
  GachamonRarity.rare: Color(0xFFC0C0C0), // silver
  GachamonRarity.pseudo: Color(0xFFFFD700), // gold
};

/// Oil-slick / trading-card holographic gradient — used for legendary card
/// borders.
const _holographicGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xFFFF80BF), // pink
    Color(0xFFFFCC66), // orange-yellow
    Color(0xFFB8E994), // mint
    Color(0xFF7FC2FF), // sky blue
    Color(0xFFC39BD3), // lavender
    Color(0xFFFF80BF), // loop back to pink
  ],
);

/// Rainbow colors used by the mythical-tier shifting-rainbow gradient.
const _mythicalRainbow = <Color>[
  Color(0xFFFF4488), // hot pink
  Color(0xFFFF8844), // orange
  Color(0xFFFFD733), // gold
  Color(0xFF55CC66), // green
  Color(0xFF2AB6CC), // teal
  Color(0xFF4488FF), // blue
  Color(0xFF9955CC), // violet
  Color(0xFFFF4488), // loop back to pink
];

/// Per-element version — each surface's gradient spans its own local rect.
/// Surfaces rotate in sync but aren't spatially seamless across boundaries.
LinearGradient _mythicalRainbowGradient(double phase) {
  return LinearGradient(
    colors: _mythicalRainbow,
    transform: GradientRotation(phase * 2 * math.pi),
  );
}

/// Card-coordinated variant — every surface on the same card samples
/// from one virtual gradient that spans the whole card, rotated by the
/// shared [phase]. [elementOffsetInCard] is the surface's top-left in
/// card coordinates; the generated shader's begin/end are translated to
/// the surface's own local space so a point in element coords lines up
/// with the same point in card coords.
///
/// With every mythical surface constructed via this helper, the rainbow
/// is seamless: the color at (card.x, card.y) is identical whether it's
/// rendered through the border ring, the sprite frame, the banner, or
/// the chip.
Gradient _mythicalRainbowForElement({
  required double cardWidth,
  required double cardHeight,
  required double phase,
  required Offset elementOffsetInCard,
}) {
  // phase is already 0..1 per rotation (caller sets its own period).
  final angle = phase * 2 * math.pi;
  final cx = cardWidth / 2;
  final cy = cardHeight / 2;
  // Use the card's actual diagonal so a gradient point at the chip's real
  // Y (near cardHeight) samples the same color as a point just above it.
  final diag =
      math.sqrt(cardWidth * cardWidth + cardHeight * cardHeight);
  final dx = math.cos(angle);
  final dy = math.sin(angle);
  final cardBegin = Offset(cx - dx * diag / 2, cy - dy * diag / 2);
  final cardEnd = Offset(cx + dx * diag / 2, cy + dy * diag / 2);
  return _CardWideRainbow(
    shaderBegin: cardBegin - elementOffsetInCard,
    shaderEnd: cardEnd - elementOffsetInCard,
  );
}

/// Gradient subclass that emits a ui.Gradient.linear with caller-provided
/// begin/end points. Extends LinearGradient so we inherit scale / lerpFrom
/// / lerpTo; we only override createShader to bypass the normal
/// Alignment-within-rect math and use absolute points in the rect's local
/// coord system. Used by mythical surfaces so each shader samples the
/// same card-wide coordinate system.
class _CardWideRainbow extends LinearGradient {
  final Offset shaderBegin;
  final Offset shaderEnd;
  const _CardWideRainbow({
    required this.shaderBegin,
    required this.shaderEnd,
  }) : super(colors: _mythicalRainbow);

  // ui.Gradient.linear requires explicit stops when colors.length > 2. The
  // mythical rainbow has 8 entries, so we compute even-spaced stops here.
  static final List<double> _evenStops = List<double>.generate(
    _mythicalRainbow.length,
    (i) => i / (_mythicalRainbow.length - 1),
  );

  @override
  Shader createShader(Rect rect, {TextDirection? textDirection}) {
    return ui.Gradient.linear(
      shaderBegin + rect.topLeft,
      shaderEnd + rect.topLeft,
      colors,
      _evenStops,
      TileMode.mirror,
    );
  }

  // LinearGradient's `==` checks `begin`/`end`/`tileMode` which are all the
  // defaults for our subclass — that would make every _CardWideRainbow
  // compare equal regardless of shaderBegin/shaderEnd, so Flutter skips the
  // BoxDecoration repaint on phase change. Override so every different set
  // of shader points is treated as a distinct gradient.
  @override
  bool operator ==(Object other) =>
      other is _CardWideRainbow &&
      other.shaderBegin == shaderBegin &&
      other.shaderEnd == shaderEnd;

  @override
  int get hashCode => Object.hash(shaderBegin, shaderEnd);
}

/// Gradient used on the legendary-tier rarity chip. A small slice of the
/// rainbow (lavender → pink) matching the border's end-of-gradient.
const _legendaryChipGradient = LinearGradient(
  begin: Alignment.bottomLeft,
  end: Alignment.centerRight,
  colors: [
    Color(0xFFE18EC9), // user-picked left stop
    Color(0xFFFF80BF), // pink
  ],
);

/// Returns the border gradient for tiers that don't use a solid color,
/// or `null` if the tier has a solid color in [_rarityBorderColors].
/// [phase] is the clock's 0..1 cycle; legendary ignores it (static rainbow)
/// while mythical uses it to rotate the rainbow over time.
Gradient? _rarityBorderGradient(GachamonRarity r, [double phase = 0]) {
  if (r == GachamonRarity.legendary) return _holographicGradient;
  if (r == GachamonRarity.mythical) return _mythicalRainbowGradient(phase);
  return null;
}

/// Matching chip gradient for the gradient-border tiers.
Gradient? _rarityChipGradient(GachamonRarity r, [double phase = 0]) {
  if (r == GachamonRarity.legendary) return _legendaryChipGradient;
  if (r == GachamonRarity.mythical) return _mythicalRainbowGradient(phase);
  return null;
}

/// Official-ish Gachamon type colors, used for the gachadex-card background.
const typeColors = <String, Color>{
  'Normal': Color(0xFFA8A878),
  'Fire': Color(0xFFF08030),
  'Water': Color(0xFF6890F0),
  'Electric': Color(0xFFF8D030),
  'Grass': Color(0xFF78C850),
  'Ice': Color(0xFF98D8D8),
  'Fighting': Color(0xFFC03028),
  'Poison': Color(0xFFA040A0),
  'Ground': Color(0xFFE0C068),
  'Flying': Color(0xFFA890F0),
  'Psychic': Color(0xFFF85888),
  'Bug': Color(0xFFA8B820),
  'Rock': Color(0xFFB8A038),
  'Ghost': Color(0xFF705898),
  'Dragon': Color(0xFF7038F8),
  'Dark': Color(0xFF2E2E36),
  'Steel': Color(0xFFB8B8D0),
  'Fairy': Color(0xFFEE99AC),
};

/// Background decoration for a gachamon's gachadex card based on its type(s).
/// Single type → solid color. Dual type → vertical gradient, type 1 on top,
/// type 2 on bottom, ombré'd through the middle.
BoxDecoration _typeBackground(Gachamon pk) {
  final c1 = typeColors[pk.type1] ?? const Color(0xFFC0C0C0);
  final c2 = pk.type2 != null ? typeColors[pk.type2] : null;
  if (c2 == null) {
    return BoxDecoration(color: c1);
  }
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      // Flat top-half → ombré band → flat bottom-half.
      colors: [c1, c1, c2, c2],
      stops: const [0.0, 0.35, 0.65, 1.0],
    ),
  );
}

/// Same as [_typeBackground] but at reduced opacity — used as a tint layer
/// painted ON TOP of the card-texture image so the card still reads as
/// type-colored while the watercolor texture shows through underneath.
BoxDecoration _typeBackgroundTint(Gachamon pk) {
  const tintAlpha = 0.55;
  final c1 = (typeColors[pk.type1] ?? const Color(0xFFC0C0C0))
      .withValues(alpha: tintAlpha);
  final c2 = pk.type2 != null
      ? typeColors[pk.type2]!.withValues(alpha: tintAlpha)
      : null;
  if (c2 == null) {
    return BoxDecoration(color: c1);
  }
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [c1, c1, c2, c2],
      stops: const [0.0, 0.35, 0.65, 1.0],
    ),
  );
}

/// Filesystem path for the card-texture image used as the card background.
/// User is expected to save the texture at `<projectRoot>/assets/gachamon/
/// card_texture.png`. If the file isn't present, DecorationImage.onError
/// swallows the failure and the tint/type color alone shows.
String _cardTexturePath() => p.join(
      PathService.assetsDir,
      'gachamon',
      'card_texture.png',
    );

/// Renders a Gachamon's name in PressStart2P with special-case handling for
/// the only two species whose canonical names include a non-ASCII glyph
/// PressStart2P doesn't ship: Nidoran ♀ (#29) and Nidoran ♂ (#32). The
/// gender symbol is split out and rendered in Segoe UI Symbol at a slightly
/// larger font with a manual baseline nudge so it visually centers against
/// the pixel-font letters.
class _NameTitle extends StatelessWidget {
  final String name;
  final double fontSize;
  const _NameTitle({required this.name, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      fontFamily: 'PressStart2P',
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      color: Colors.black,
    );
    // Look for ♀ or ♂ anywhere in the name (currently only Nidoran).
    final genderRe = RegExp(r'[♀♂]');
    final m = genderRe.firstMatch(name);
    if (m == null) {
      return Text(name,
          style: baseStyle, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    final before = name.substring(0, m.start).trimRight();
    final symbol = m.group(0)!;
    final after = name.substring(m.end).trimLeft();
    final symbolStyle = TextStyle(
      fontFamily: 'Segoe UI Symbol',
      fontFamilyFallback: const ['Cambria Math', 'Arial'],
      fontSize: fontSize * 1.15,
      fontWeight: FontWeight.w700,
      color: Colors.black,
      // Nudge the symbol up so its visual midline matches the pixel-font
      // glyphs (Segoe UI Symbol sits low otherwise).
      height: 1.0,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(before,
              style: baseStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 4),
        // baseline-shift the symbol up a hair via Transform.translate.
        Transform.translate(
          offset: const Offset(0, -2),
          child: Text(symbol, style: symbolStyle),
        ),
        if (after.isNotEmpty) ...[
          const SizedBox(width: 4),
          Flexible(
            child: Text(after,
                style: baseStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ],
    );
  }
}
