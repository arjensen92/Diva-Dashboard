import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../gachamon/gachamon_data.dart';
import '../services/path_service.dart';
import '../services/gachamon_game_service.dart';
import '../theme/app_colors.dart';
import '../widgets/full_screen_overlay.dart';
import '../widgets/gachadex_card.dart';
import '../widgets/sticker_sprite.dart';
import '../widgets/win95.dart';

/// The Gachamon gachapon screen — shows the 151-slot gachadex grid and a
/// gachaball counter + catch button that opens [_CatchingDialog]. The catch
/// dialog, card display, and all the effects (sparkles, holographic
/// shimmer, rarity gradients) live in companion files: `gachadex_card.dart`,
/// `sticker_sprite.dart`, `holographic.dart`, `render_layers.dart`.
class GachamonFullScreen extends ConsumerStatefulWidget {
  const GachamonFullScreen({super.key});

  @override
  ConsumerState<GachamonFullScreen> createState() => _GachamonFullScreenState();
}

class _GachamonFullScreenState extends ConsumerState<GachamonFullScreen> {
  final ScrollController _scrollController = ScrollController();

  /// Tracks whether we've already warmed the image cache for gachamon sprites.
  /// First time the user opens the full screen we batch-precache every sprite
  /// + gachaball icons so dex card opens are instant. Subsequent opens skip
  /// the warmup since the entries are still in PaintingBinding.imageCache.
  static bool _imageCacheWarmed = false;

  @override
  void initState() {
    super.initState();
    if (!_imageCacheWarmed) {
      _imageCacheWarmed = true;
      WidgetsBinding.instance.addPostFrameCallback(_warmImageCache);
    }
  }

  /// Warm Flutter's shared image cache with the icons that the catch
  /// dialog and dex card open paths use via Image.file. Only icons are
  /// precached — gachamon sprites in the grid go through StickerSprite,
  /// which uses ui.instantiateImageCodec directly (bypassing imageCache),
  /// so precaching them via FileImage is pure disk thrash with no payoff.
  ///
  /// Gachamon sprites warm on-demand: each StickerSprite loads its sprite
  /// in initState (visible cells only, since the GridView is lazy).
  /// Dex card opens via Image.file — first open per gachamon is a
  /// one-time decode; subsequent opens hit imageCache.
  Future<void> _warmImageCache(Duration _) async {
    if (!mounted) return;

    // Pokeball icons. Tiny files used by the status row, catch dialog
    // title, counter, and main catch button. Awaited so they're
    // guaranteed in the cache before the catch dialog can render.
    for (final path in [
      p.join(PathService.iconsDir, 'gachaball_icon.png'),
      p.join(PathService.iconsDir, 'gachaball.png'),
    ]) {
      if (!mounted) return;
      try {
        await precacheImage(FileImage(File(path)), context);
      } catch (_) {/* swallow */}
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onCatch() {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const _CatchingDialog(),
    );
  }

  void _jumpToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gachamonGameProvider);
    return FullScreenOverlay(
      title: 'Gachamon',
      // Own scrolling — pinned status bar stays visible while only the
      // The grid scrolls itself — pinned status row stays visible.
      scrollable: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _statusRow(game),
            const SizedBox(height: 12),
            // Grid does its own scrolling now (no shrinkWrap, no parent
            // SingleChildScrollView). That's the difference between
            // building 1000+ cells on every frame vs. only the ~12
            // currently visible — the dex screen used to lock the UI
            // thread for hundreds of milliseconds on entry because the
            // shrinkWrap pattern forced every off-screen StickerSprite
            // to paint anyway.
            Expanded(
              child: _GachadexGrid(
                game: game,
                scrollController: _scrollController,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(GachamonGameState game) {
    // Count distinct Gachadex IDs — any form (base, alt, regional, mega,
    // gmax) counts toward completion.
    final totalIds = gachadex.map((p) => p.id).toSet().length;
    final caughtIds = game.catchOrder
        .map((k) {
          final c = k.indexOf(':');
          return c < 0 ? k : k.substring(0, c);
        })
        .toSet()
        .length;
    return Row(
      children: [
        Image.file(
          File(p.join(PathService.iconsDir, 'gachaball_icon.png')),
          width: 36,
          height: 36,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.catching_pokemon,
            color: Colors.red,
            size: 36,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${game.gachaballs} Gachaball${game.gachaballs == 1 ? '' : 's'}',
          style:
              const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        Text(
          'Caught: $caughtIds / $totalIds',
          style: const TextStyle(fontSize: 16, color: AppColors.textMuted),
        ),
        const SizedBox(width: 16),
        Material(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(AppColors.radiusSm),
          child: InkWell(
            onTap: _onCatch,
            borderRadius: BorderRadius.circular(AppColors.radiusSm),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Text(
                'Catch!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: AppColors.surfaceHover,
          borderRadius: BorderRadius.circular(AppColors.radiusSm),
          child: InkWell(
            onTap: _jumpToTop,
            borderRadius: BorderRadius.circular(AppColors.radiusSm),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Icon(
                Icons.arrow_upward,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The Gachadex grid itself. Stateless because the grid is now natively
/// lazy — without shrinkWrap+NeverScrollable, GridView.builder only calls
/// itemBuilder for the ~12 cells currently visible (plus a small lookahead
/// buffer). No more manual batching, no more layout-the-world-up-front.
class _GachadexGrid extends StatelessWidget {
  final GachamonGameState game;
  final ScrollController scrollController;
  const _GachadexGrid({required this.game, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 20),
      // Pre-build cells well above and below the viewport so scrolling
      // doesn't hitch waiting on async sprite decodes. Default cacheExtent
      // is ~250 px (about 2 rows beyond the viewport); 2000 px gives us
      // ~16 extra rows in each direction, covering normal swipe/scroll
      // velocities without making the off-screen builds visible.
      cacheExtent: 2000,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 12,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: gachadex.length,
      itemBuilder: (context, i) {
        final pk = gachadex[i];
        final count = game.caught[pk.uniqueKey] ?? 0;
        final holoCount = game.holo[pk.uniqueKey] ?? 0;
        final hasIt = count > 0;
        final hasHolo = holoCount > 0;
        Widget? sprite;
        if (hasIt) {
          sprite = StickerSprite(
            spritePath: gachamonSpritePath(pk),
            isHolo: hasHolo,
          );
        }
        final cell = Container(
          decoration: BoxDecoration(
            // Owned cells: transparent so the sticker's own white border
            // and card-texture fill stand on their own. Unowned cells
            // keep the dark placeholder background.
            color: hasIt ? null : Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
            border: hasIt
                ? null
                : Border.all(color: AppColors.border.withValues(alpha: 0.3)),
          ),
          padding: const EdgeInsets.all(2),
          child: sprite ??
              Center(
                child: Text(
                  '#${pk.id}',
                  style: const TextStyle(
                    fontFamily: 'PressStart2P',
                    fontSize: 8,
                    color: Colors.white54,
                  ),
                ),
              ),
        );
        // Build tooltip with mixed fonts so Nidoran ♀/♂ render in
        // Segoe UI Symbol (the rest of the tooltip uses the default font).
        InlineSpan tooltipSpans;
        if (!hasIt) {
          tooltipSpans = const TextSpan(text: '???');
        } else {
          final tail = hasHolo ? ' ×$count  ✦ ×$holoCount' : ' ×$count';
          final genderRe = RegExp(r'[♀♂]');
          final m = genderRe.firstMatch(pk.name);
          if (m == null) {
            tooltipSpans = TextSpan(text: '${pk.name}$tail');
          } else {
            final before = pk.name.substring(0, m.start).trimRight();
            final symbol = m.group(0)!;
            final after = pk.name.substring(m.end).trimLeft();
            tooltipSpans = TextSpan(children: [
              TextSpan(text: '$before '),
              TextSpan(
                text: symbol,
                style: const TextStyle(fontFamily: 'Segoe UI Symbol'),
              ),
              if (after.isNotEmpty) TextSpan(text: ' $after'),
              TextSpan(text: tail),
            ]);
          }
        }
        return Tooltip(
          richMessage: tooltipSpans,
          textStyle: const TextStyle(color: Colors.white),
          child: hasIt
              ? GestureDetector(
                  onTap: () => showGachadexCard(context, pk, count,
                      isHolo: hasHolo),
                  child: MouseRegion(cursor: SystemMouseCursors.click, child: cell),
                )
              : cell,
        );
      },
    );
  }
}

/// The catching window. Shows remaining gachaballs and a big clickable
/// gachaball — each tap consumes a ball, rolls a random gachamon, and
/// reveals the result in-place with the rarity chip and New! / ×N badge.
class _CatchingDialog extends ConsumerStatefulWidget {
  const _CatchingDialog();

  @override
  ConsumerState<_CatchingDialog> createState() => _CatchingDialogState();
}

class _CatchingDialogState extends ConsumerState<_CatchingDialog>
    with TickerProviderStateMixin {
  Gachamon? _lastCaught;
  int _lastCaughtCount = 0;
  int _lastCaughtHoloCount = 0;
  bool _lastCaughtHolo = false;
  List<CatchRoll> _skippedRolls = const [];
  bool _rolling = false;
  late AnimationController _shakeController;
  late AnimationController _idleShakeController;
  Timer? _idleTimer;
  final math.Random _idleRng = math.Random();
  // Separate AudioPlayers so the shake / throw / catch sounds can overlap.
  final AudioPlayer _catchAudio = AudioPlayer();
  final AudioPlayer _throwAudio = AudioPlayer();
  final AudioPlayer _shakeAudio = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _idleShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _scheduleIdleShake();
  }

  void _scheduleIdleShake() {
    _idleTimer?.cancel();
    // Random 2–4s gap between shakes so it feels alive rather than metronomic.
    final delayMs = 2000 + _idleRng.nextInt(2000);
    _idleTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      final gachaballs = ref.read(gachamonGameProvider).gachaballs;
      if (!_rolling && gachaballs > 0) {
        _idleShakeController.forward(from: 0);
        _playSound(_shakeAudio, 'ballshake.mp3', _shakeVolume);
      }
      _scheduleIdleShake();
    });
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _shakeController.dispose();
    _idleShakeController.dispose();
    _catchAudio.dispose();
    _throwAudio.dispose();
    _shakeAudio.dispose();
    super.dispose();
  }

  // Volumes tuned to match each other and sit below system volume defaults.
  static const double _catchVolume = 0.22;
  static const double _throwVolume = 0.18;
  static const double _shakeVolume = 0.13;

  Future<void> _playSound(
      AudioPlayer player, String fileName, double volume) async {
    final path = p.join(PathService.assetsDir, 'sounds', fileName);
    try {
      await player.setVolume(volume);
      await player.play(DeviceFileSource(path));
    } catch (e) {
      // Swallow audio errors; sound is non-critical.
    }
  }

  Future<void> _throwBall() async {
    if (_rolling) return;
    if (ref.read(gachamonGameProvider).gachaballs <= 0) return;
    setState(() => _rolling = true);
    // Throw SFX fires as the user clicks, before the reveal animation.
    _playSound(_throwAudio, 'throw.mp3', _throwVolume);
    // Shake the ball before revealing
    _shakeController.forward(from: 0);
    await Future.delayed(const Duration(milliseconds: 450));
    final result = ref.read(gachamonGameProvider.notifier).spendBallAndCatch();
    if (!mounted) return;
    if (result == null) {
      setState(() => _rolling = false);
      return;
    }
    final caught = result.gachamon;

    // Pre-cache every image the new card will paint BEFORE we swap
    // _lastCaught. The old card (or, for the first catch, the empty
    // slot) stays visible during this wait so the swap is atomic — old
    // → new in one frame, no SizedBox placeholder, no dialog reflow
    // from a placeholder of the wrong size.
    await GachadexCard.precacheImagesFor(context, caught);
    if (!mounted) return;

    final state = ref.read(gachamonGameProvider);
    final count = state.caught[caught.uniqueKey] ?? 1;
    final holoCount = state.holo[caught.uniqueKey] ?? 0;
    // Celebrate first-time catches with the sound effect.
    if (count == 1) {
      _playSound(_catchAudio, 'catch.mp3', _catchVolume);
    }
    setState(() {
      _lastCaught = caught;
      _lastCaughtCount = count;
      _lastCaughtHoloCount = holoCount;
      _lastCaughtHolo = result.isHolo;
      _skippedRolls = result.skipped;
      _rolling = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gachamonGameProvider);
    final gachaballPath = p.join(PathService.iconsDir, 'gachaball.png');
    final canCatch = game.gachaballs > 0 && !_rolling;
    // Main catch panel is a fixed 380-wide SizedBox so the Dialog centers
    // it on screen at a constant position. The side window (when present)
    // is layered as a Positioned child of the Stack with Clip.none, so it
    // hangs off the right edge of the main panel without shifting it —
    // the combined view ends up off-center to the right while the catch
    // panel itself stays anchored at screen center.
    const double mainPanelWidth = 380;
    const double sidePanelGap = 12;
    return Dialog(
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: mainPanelWidth,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Win95Panel(
              child: SingleChildScrollView(
                child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Win95TitleBar(
              title: 'Catch Gachamon!',
              titleFontSize: 14,
              buttonSize: 22,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              leading: SizedBox(
                width: 14,
                height: 14,
                child: Image.file(File(gachaballPath), fit: BoxFit.contain),
              ),
              onClose: () => Navigator.of(context).pop(),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pokeball count readout
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: Image.file(File(gachaballPath), fit: BoxFit.contain),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '× ${game.gachaballs}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Clickable gachaball
                  GestureDetector(
                    onTap: canCatch ? _throwBall : null,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_shakeController, _idleShakeController]),
                      builder: (context, child) {
                        // Rolling-catch shake — quick left/right flurry.
                        final rollT = _shakeController.value;
                        final rollAngle =
                            rollT == 0 ? 0.0 : math.sin(rollT * math.pi * 6) * 0.25;
                        // Idle shake — a brief roll back-and-forth. Angle
                        // and translation move together so it looks like
                        // the ball's rocking on the ground.
                        final idleT = _idleShakeController.value;
                        final idleWave =
                            idleT == 0 ? 0.0 : math.sin(idleT * math.pi * 3);
                        final idleAngle = idleWave * 0.12;
                        final idleDx = idleWave * 14;
                        return Transform.translate(
                          offset: Offset(idleDx, 0),
                          child: Transform.rotate(
                            angle: rollAngle + idleAngle,
                            child: child,
                          ),
                        );
                      },
                      child: MouseRegion(
                        cursor: canCatch
                            ? SystemMouseCursors.click
                            : SystemMouseCursors.forbidden,
                        child: Opacity(
                          opacity: canCatch ? 1.0 : 0.35,
                          child: SizedBox(
                            width: 160,
                            height: 160,
                            child: Image.file(
                              File(gachaballPath),
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    game.gachaballs <= 0
                        ? 'No gachaballs left — come back on the hour!'
                        : _rolling
                            ? '...'
                            : (_lastCaught == null
                                ? 'Click the gachaball to catch!'
                                : 'Click again to catch another!'),
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            // The catch result — banner + card. Rendered conditionally
            // (no fixed slot) so the dialog wraps tightly to the actual
            // card's natural height — no empty space at the bottom.
            //
            // No `!_rolling` guard: keeping the previous card visible
            // during the throw animation means the swap to the new card
            // happens atomically in one frame. _throwBall awaits a
            // precache for the new card's images before flipping
            // _lastCaught, so the dialog only resizes once — at the
            // moment the new card is fully ready to render.
            if (_lastCaught != null) ...[
              // Status banner. First-time catches get the red "New Catch!"
              // flair; duplicates get a gray banner with the tooltip-style
              // count readout (`Name ×N  ✦ ×holo`).
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: _lastCaughtCount == 1
                        ? Colors.red.shade600
                        : Colors.grey.shade600,
                  ),
                  child: Text(
                    _lastCaughtCount == 1
                        ? 'New Catch! ${_lastCaught!.name}'
                        : 'Gotcha! ${_lastCaught!.name} ×$_lastCaughtCount'
                            '${_lastCaughtHoloCount > 0 ? '  ✦ ×$_lastCaughtHoloCount' : ''}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                child: GachadexCard(
                  gachamon: _lastCaught!,
                  catchCount: _lastCaughtCount,
                  isHolo: _lastCaughtHolo,
                ),
              ),
            ],
          ],
        ),
        ),
        ),
            // Side window — only when the duplicate-protection loop rejected
            // any rolls. Positioned so it hangs off the right edge of the
            // main panel without affecting its layout. Anchored at top: 0
            // so it tops-aligns with the main panel header.
            if (_skippedRolls.isNotEmpty && !_rolling)
              Positioned(
                left: mainPanelWidth + sidePanelGap,
                top: 0,
                child: _SkippedRollsWindow(rolls: _skippedRolls),
              ),
          ],
        ),
      ),
    );
  }
}

/// Side-panel Win95 window showing every roll the duplicate-protection
/// loop rejected before settling on the kept catch. Each rejected roll
/// renders as a tiny full-gachadex card so the player can see what they
/// "narrowly missed" — ordered chronologically (first reroll on top).
class _SkippedRollsWindow extends StatelessWidget {
  final List<CatchRoll> rolls;
  const _SkippedRollsWindow({required this.rolls});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200, maxHeight: 720),
      child: Win95Panel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Win95TitleBar(
              title: 'Skipped (×${rolls.length})',
              titleFontSize: 14,
              buttonSize: 22,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              leading: const Icon(Icons.refresh, size: 14, color: Colors.white),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    for (int i = 0; i < rolls.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      _SkippedRollMiniCard(roll: rolls[i]),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tiny [GachadexCard] — same widget, scaled down via Transform inside
/// an OverflowBox so the card lays out at its natural ~352×620 footprint
/// but paints into a smaller fixed-width area. ClipRect catches the
/// occasional bottom-edge overflow on tall cards (long dex entries).
class _SkippedRollMiniCard extends StatelessWidget {
  final CatchRoll roll;
  const _SkippedRollMiniCard({required this.roll});

  static const _naturalWidth = 352.0;
  static const _naturalHeight = 660.0;
  static const _renderWidth = 160.0;

  @override
  Widget build(BuildContext context) {
    const scale = _renderWidth / _naturalWidth;
    // Force text to lay out at the same scale as the rest of the card.
    // GachadexCard's font sizes are baked-in absolute pixel values
    // (fontSize 14, 9, 7…) — Transform.scale shrinks them at paint time,
    // but the text is still laid out at its full character widths and
    // can read as "too big" relative to the tiny card. The textScaler
    // stacks on top of the Transform, landing text around 0.2× of the
    // original. Illegible on purpose; this is just a thumbnail.
    return SizedBox(
      width: _renderWidth,
      height: _naturalHeight * scale,
      child: ClipRect(
        child: OverflowBox(
          maxWidth: _naturalWidth,
          maxHeight: _naturalHeight,
          alignment: Alignment.topLeft,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(0.45)),
              child: SizedBox(
                width: _naturalWidth,
                child: GachadexCard(
                  gachamon: roll.gachamon,
                  catchCount: 1,
                  isHolo: roll.isHolo,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
