import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../theme/app_colors.dart';
import '../theme/animated_backgrounds.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/full_screen_overlay.dart';
import '../widgets/calendar_card.dart';
import '../widgets/tasks_card.dart';
import '../widgets/spotify_card.dart';
import '../widgets/gachamon_card.dart';
import '../gachamon/gachamon_data.dart';
import '../services/gachamon_game_service.dart';
import '../widgets/sparkle_overlay.dart' show OverlayImage;
import '../widgets/sparkle_layer.dart';
import '../widgets/sticker_layer.dart';
import '../widgets/win95_taskbar.dart';
import '../widgets/win95.dart';
import '../widgets/sticker_panel_widgets.dart';
import '../services/overlay_service.dart';
import '../services/path_service.dart';
import '../providers/effects_quality.dart';
import '../widgets/settings_panel.dart';
import 'calendar_full_screen.dart';
import 'tasks_full_screen.dart';
import 'spotify_full_screen.dart';
import 'gachamon_full_screen.dart';
import '../widgets/sticker_sprite.dart';

// Current theme provider — randomized on boot and every hour
final themeProvider = StateNotifierProvider<ThemeNotifier, DashboardTheme>((ref) {
  return ThemeNotifier(ref);
});

class ThemeNotifier extends StateNotifier<DashboardTheme> {
  final Ref ref;
  Timer? _timer;
  List<String> _bgImages = [];

  ThemeNotifier(this.ref) : super(DashboardTheme(randomAccent())) {
    _init();
  }

  Future<void> _init() async {
    _bgImages = await getBackgroundImages();
    randomize(); // initial randomize with images loaded
    _timer = Timer.periodic(const Duration(hours: 1), (_) => randomize());
  }

  void randomize() {
    final rng = math.Random();
    // YouTube backgrounds only enter the random pool when the video
    // background is enabled — when it's off, the dashboard never
    // auto-spins-up the WebView player.
    final allowYouTube = ref.read(videoBackgroundEnabledProvider);
    final ytPoolSize = allowYouTube ? youtubeBackgrounds.length : 0;
    final totalOptions = themePalette.length + _bgImages.length + ytPoolSize;
    final pick = rng.nextInt(totalOptions);
    if (pick < themePalette.length) {
      state = DashboardTheme(themePalette[pick]);
    } else if (pick < themePalette.length + _bgImages.length) {
      final img = _bgImages[pick - themePalette.length];
      state = DashboardTheme(randomAccent(), backgroundImage: img);
    } else {
      // Picked a YouTube video background
      final yt = youtubeBackgrounds[pick - themePalette.length - _bgImages.length];
      // Random start position — at least 1 hour before the end
      final maxStart = (yt.durationSeconds - 3600).clamp(0, yt.durationSeconds);
      final startSeconds = maxStart > 0 ? rng.nextInt(maxStart) : 0;
      state = DashboardTheme(randomAccent(), youtubeBackground: yt, youtubeStartSeconds: startSeconds);
    }
  }

  void setYouTubeBackground(YouTubeBackground yt) {
    final rng = math.Random();
    final maxStart = (yt.durationSeconds - 3600).clamp(0, yt.durationSeconds);
    final startSeconds = maxStart > 0 ? rng.nextInt(maxStart) : 0;
    state = DashboardTheme(randomAccent(), youtubeBackground: yt, youtubeStartSeconds: startSeconds);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// Sparkle images provider — small sparkle textures scattered across background
final sparkleImagesProvider = StateProvider<List<PlacedOverlay>>((ref) => []);

// Graphics images provider — larger gifs/images placed around the edges ABOVE cards
final graphicsImagesProvider = StateProvider<List<PlacedOverlay>>((ref) => []);

// Grid mode toggle
final gridModeProvider = StateProvider<bool>((ref) => false);

// Sticker edit mode — when true, stickers are draggable
final stickerEditModeProvider = StateProvider<bool>((ref) => false);

// Sticker panel open — shows the sticker picker drawer
final stickerPanelOpenProvider = StateProvider<bool>((ref) => false);

// Which sticker tab is active in the drawer. `'graphics'` = normal sticker
// graphics, `'gachamon'` = caught Gachamon sprites.
final stickerTabProvider = StateProvider<String>((ref) => 'graphics');

// Start menu open
final startMenuOpenProvider = StateProvider<bool>((ref) => false);

// Background picker open
final bgPickerOpenProvider = StateProvider<bool>((ref) => false);

// (Master effects toggle removed — superseded by per-effect quality
// providers in effects_quality.dart. Setting all three to off is the
// equivalent of the old "Effects: Off" state.)

class _CardDef {
  final String title;
  final IconData icon;
  final Widget Function() cardBuilder;
  final Widget Function() fullScreenBuilder;
  final double chromeOpacity;
  const _CardDef({required this.title, required this.icon, required this.cardBuilder, required this.fullScreenBuilder, this.chromeOpacity = 1.0});
}

final _cards = [
  _CardDef(title: 'Calendar', icon: Icons.calendar_today, cardBuilder: () => const CalendarCardContent(), fullScreenBuilder: () => const CalendarFullScreen()),
  _CardDef(title: 'Lists', icon: Icons.checklist, cardBuilder: () => const TasksCardContent(), fullScreenBuilder: () => const TasksFullScreen()),
  _CardDef(title: 'Gachamon', icon: Icons.catching_pokemon, cardBuilder: () => const GachamonCardContent(), fullScreenBuilder: () => const GachamonFullScreen()),
  _CardDef(title: 'Spotify', icon: Icons.music_note, cardBuilder: () => const SpotifyCardContent(), fullScreenBuilder: () => const SpotifyFullScreen(), chromeOpacity: 0.35),
];

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  late PageController _pageController;
  int _currentPage = 0;
  double _scrollOffset = 0;
  List<String> _sparkleFiles = [];
  List<String> _graphicFiles = [];
  final AudioPlayer _pcAudio = AudioPlayer();
  static const double _pcVolume = 0.18;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.75, initialPage: 5000);
    _pageController.addListener(_onScroll);
    _loadOverlays();
  }

  void _onScroll() {
    if (_pageController.hasClients && _pageController.page != null) {
      setState(() => _scrollOffset = _pageController.page!);
    }
  }

  Future<void> _loadOverlays() async {
    // Delay so UI renders first.
    await Future.delayed(const Duration(seconds: 1));
    _sparkleFiles = await OverlayService.listImageFiles(PathService.sparklesDir);
    _graphicFiles = await OverlayService.listImageFiles(PathService.graphicsDir);
    if (!mounted) return;

    // Load graphics first (fewer, more important).
    _randomizeGraphicsOnly(_graphicFiles);

    // Then load sparkles in batches to avoid freezing.
    await Future.delayed(const Duration(seconds: 4));
    if (mounted) await _randomizeSparklesOnly(_sparkleFiles);
  }

  void shuffleEverything() {
    ref.read(themeProvider.notifier).randomize();
    _randomizeGraphicsOnly(_graphicFiles);
    ref.read(sparkleImagesProvider.notifier).state = []; // clear first
    _randomizeSparklesOnly(_sparkleFiles); // loads in batches
  }

  Future<void> _randomizeSparklesOnly(List<String> sparkleFiles) async {
    final target = ref.read(sparkleQualityProvider).sparkleCount;
    if (target <= 0) {
      ref.read(sparkleImagesProvider.notifier).state = const [];
      return;
    }
    await for (final batch in OverlayService.generateSparkleBatches(
      sparkleFiles,
      targetCount: target,
    )) {
      if (!mounted) return;
      ref.read(sparkleImagesProvider.notifier).state = batch;
    }
  }

  void _randomizeOverlays(List<String> sparkleFiles, List<String> graphicFiles) {
    _randomizeSparklesOnly(sparkleFiles);
    _randomizeGraphicsOnly(graphicFiles);
  }

  void _randomizeGraphicsOnly(List<String> graphicFiles) {
    final perCard = ref.read(stickerQualityProvider).stickersPerCard;
    if (perCard <= 0) {
      ref.read(graphicsImagesProvider.notifier).state = const [];
      return;
    }
    ref.read(graphicsImagesProvider.notifier).state =
        OverlayService.generateGraphics(
      graphicFiles,
      _cards.length,
      perCardCap: perCard,
    );
  }

  /// Recompute sparkles + stickers when their quality settings change.
  /// Called from the Settings panel via a [ref.listen] hook so the user
  /// sees the new tier immediately without needing to shuffle the theme.
  void _onSparkleQualityChanged() {
    ref.read(sparkleImagesProvider.notifier).state = const [];
    PaintingBinding.instance.imageCache.clear();
    _randomizeSparklesOnly(_sparkleFiles);
  }

  void _onStickerQualityChanged() {
    PaintingBinding.instance.imageCache.clear();
    _randomizeGraphicsOnly(_graphicFiles);
  }

  @override
  void dispose() {
    _pageController.removeListener(_onScroll);
    _pageController.dispose();
    _pcAudio.dispose();
    super.dispose();
  }

  /// Sprite paths for every caught gachamon, sorted by Gachadex ID (then by
  /// form tag so alt forms follow their base).
  List<String> _gachamonStickers(WidgetRef ref) {
    final game = ref.watch(gachamonGameProvider);
    final caught = <Gachamon>[];
    for (final key in game.catchOrder) {
      final pk = gachamonByKey(key);
      if (pk != null) caught.add(pk);
    }
    caught.sort((a, b) {
      if (a.id != b.id) return a.id.compareTo(b.id);
      // Base form (null) before any alt form; then alphabetical by form tag.
      if (a.form == null && b.form != null) return -1;
      if (a.form != null && b.form == null) return 1;
      return (a.form ?? '').compareTo(b.form ?? '');
    });
    return caught.map(gachamonSpritePath).toList();
  }

  /// Active sticker list based on the selected tab in the drawer.
  List<String> _stickersForTab(WidgetRef ref, String tab) {
    if (tab == 'gachamon') return _gachamonStickers(ref);
    return _graphicFiles;
  }

  /// Set of sprite paths the user owns as holographic, used to decide
  /// whether a gachamon sticker gets the holo shimmer. Computed once per
  /// build so the O(N) lookup is cheap at sticker-render time.
  Set<String> _holoSpritePaths(WidgetRef ref) {
    final game = ref.watch(gachamonGameProvider);
    final result = <String>{};
    for (final entry in game.holo.entries) {
      if (entry.value <= 0) continue;
      final pk = gachamonByKey(entry.key);
      if (pk != null) result.add(gachamonSpritePath(pk));
    }
    return result;
  }

  void _openFullScreen(BuildContext context, Widget screen) {
    // Play the PC jingle when entering the full Gachadex view.
    if (screen is GachamonFullScreen) {
      final soundPath =
          p.join(PathService.assetsDir, 'sounds', 'PC.mp3');
      _pcAudio.setVolume(_pcVolume);
      _pcAudio.play(DeviceFileSource(soundPath)).catchError((_) {});
    }
    Navigator.of(context).push(ZoomInRoute(page: screen));
  }

  void _goToPage(int direction) {
    final currentRawPage = _pageController.page?.round() ?? 1000;
    _pageController.animateToPage(currentRawPage + direction, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    // Re-randomize overlays when the hourly timer fires
    ref.listen(themeProvider, (_, __) {
      _randomizeOverlays(_sparkleFiles, _graphicFiles);
    });
    // Re-generate sparkles / stickers immediately when their quality
    // tier changes — previewing the change in the Settings panel feels
    // wrong if it doesn't take effect until the next hourly shuffle.
    ref.listen(sparkleQualityProvider, (_, __) => _onSparkleQualityChanged());
    ref.listen(stickerQualityProvider, (_, __) => _onStickerQualityChanged());

    final theme = ref.watch(themeProvider);
    final isGridMode = ref.watch(gridModeProvider);
    final isStickerPanel = ref.watch(stickerPanelOpenProvider);
    final isSettingsPanel = ref.watch(settingsPanelOpenProvider);
    // SparkleLayer reads sparkleImagesProvider internally — no local variable needed.
    final graphics = ref.watch(graphicsImagesProvider);

    final isMenuOpen = ref.watch(startMenuOpenProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => ref.read(startMenuOpenProvider.notifier).state = false,
        child: Stack(
          children: [
            // YouTube video background is rendered at the app level
            // (main.dart MaterialApp.builder) so it persists across routes.
            Column(
              children: [
                Expanded(child: AnimatedBackground(
        theme: theme,
        child: Stack(
          children: [
            // Sparkle image overlays — single painter pass, shared image cache
            const SparkleLayer(),

            Stack(
                children: [
                  // Main content
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: isGridMode ? _buildGridView(context) : _buildCarouselView(context),
                  ),

                  // Graphics + Gachamon sticker overlays — single painter
                  // pass with shared image cache. One HoloClock listener
                  // and one CustomPainter for all stickers combined.
                  if (!isGridMode) Positioned.fill(
                    child: DashboardStickerLayer(
                      stickers: graphics,
                      holoPaths: _holoSpritePaths(ref),
                      scrollOffset: _scrollOffset,
                      numCards: _cards.length,
                    ),
                  ),

                  // Nav arrows — above stickers so they're always tappable
                  if (!isGridMode) Positioned(left: 4, top: 0, bottom: 0, child: Center(child: _NavArrow(icon: Icons.chevron_left, onTap: () => _goToPage(-1)))),
                  if (!isGridMode) Positioned(right: 4, top: 0, bottom: 0, child: Center(child: _NavArrow(icon: Icons.chevron_right, onTap: () => _goToPage(1)))),
                ],
              ),

            // Sticker panel drawer — slides in from the right
            if (isStickerPanel)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 250,
                child: _buildStickerPanel(context, theme),
              ),

            // Background picker panel
            if (ref.watch(bgPickerOpenProvider))
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 280,
                child: _buildBgPicker(context, theme),
              ),

            // Settings panel — slides in from the left, same chrome as
            // the background picker. Per-effect quality sliders live here.
            if (isSettingsPanel)
              const Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 320,
                child: SettingsPanel(),
              ),
          ],
        ),
      )),
          const Win95Taskbar(),
              ],
            ),
            // Start menu popup — in outer Stack so it can render above everything and receive taps
            if (isMenuOpen)
              Positioned(
                left: 1,
                bottom: 37,
                child: Win95StartMenu(
                  isGridMode: isGridMode,
                  onStickerPanel: () { ref.read(stickerPanelOpenProvider.notifier).state = !ref.read(stickerPanelOpenProvider); },
                  onChangeBackground: () { ref.read(bgPickerOpenProvider.notifier).state = !ref.read(bgPickerOpenProvider); },
                  onShuffle: () => shuffleEverything(),
                  onToggleGrid: () { ref.read(gridModeProvider.notifier).state = !ref.read(gridModeProvider); },
                  onSettings: () { ref.read(settingsPanelOpenProvider.notifier).state = !ref.read(settingsPanelOpenProvider); },
                  onExit: () => exit(0),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStickerPanel(BuildContext context, DashboardTheme theme) {
    return Container(
      decoration: BoxDecoration(
        color: Win95.gray,
        border: const Border(
          left: BorderSide(color: Win95.white, width: 2),
          top: BorderSide(color: Win95.white, width: 2),
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(-4, 0))],
      ),
      child: Column(
        children: [
          Win95TitleBar(
            title: 'Stickers',
            titleFontSize: 12,
            height: 32,
            buttonSize: 22,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            onClose: () =>
                ref.read(stickerPanelOpenProvider.notifier).state = false,
          ),
          // Tab row — switch between Graphics and caught Gachamon
          StickerTabs(ref: ref),
          // Sticker grid — scrollable
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Win95.gray,
                border: Win95.sunkenBorder(width: 1.5),
              ),
              child: ScrollbarTheme(
                data: ScrollbarThemeData(
                  thumbColor: WidgetStateProperty.all(Win95.gray),
                  trackColor: WidgetStateProperty.all(Win95.darkGray),
                  trackBorderColor: WidgetStateProperty.all(Win95.veryDark),
                  thickness: WidgetStateProperty.all(16),
                  trackVisibility: WidgetStateProperty.all(true),
                  radius: Radius.zero,
                ),
                child: Scrollbar(
                thumbVisibility: true,
                interactive: true,
                child: Builder(builder: (context) {
                final tab = ref.watch(stickerTabProvider);
                final stickers = _stickersForTab(ref, tab);
                final isGachamonTab = tab == 'gachamon';
                final holoPaths = isGachamonTab
                    ? _holoSpritePaths(ref)
                    : const <String>{};
                return GridView.builder(
                // Extra right padding so grid items clear the 16px scrollbar
                // thumb — without this the Draggable intercepts scrollbar clicks.
                padding: const EdgeInsets.fromLTRB(6, 6, 24, 6),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                itemCount: stickers.length,
                itemBuilder: (context, i) {
                  final path = stickers[i];
                  final feedbackChild = isGachamonTab
                      ? SizedBox(
                          width: 100,
                          height: 100,
                          child: StickerSprite(
                            spritePath: path,
                            isHolo: holoPaths.contains(path),
                          ),
                        )
                      : OverlayImage(path: path, width: 100, height: 100);
                  final draggingChild = isGachamonTab
                      ? StickerSprite(
                          spritePath: path,
                          isHolo: holoPaths.contains(path),
                        )
                      : OverlayImage(path: path, fit: BoxFit.contain);
                  return Draggable<String>(
                    data: path,
                    feedback: Opacity(opacity: 0.8, child: feedbackChild),
                    childWhenDragging:
                        Opacity(opacity: 0.3, child: draggingChild),
                    onDragEnd: (details) {
                      if (!details.wasAccepted) {
                        // Dropped on the canvas (not on a DragTarget)
                        final screenW = MediaQuery.of(context).size.width;
                        final screenH = MediaQuery.of(context).size.height;
                        final cardPos = _scrollOffset % _cards.length;
                        final canvasX = (details.offset.dx / screenW) + cardPos;
                        final canvasY = details.offset.dy / screenH;
                        // Gachamon stickers drop at a fixed size so the whole
                        // collection stays visually consistent. Graphics keep
                        // the 130–200 random variance for organic placement.
                        final isGachamon = path.contains('gachamon');
                        final rng = math.Random();
                        final size = isGachamon ? 160.0 : 130 + rng.nextDouble() * 70;
                        final newSticker = PlacedOverlay(path, canvasX, canvasY, size, 0);
                        final current = ref.read(graphicsImagesProvider);
                        ref.read(graphicsImagesProvider.notifier).state = [...current, newSticker];
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFCCCCCC)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: isGachamonTab
                          ? StickerSprite(
                              spritePath: path,
                              isHolo: holoPaths.contains(path),
                            )
                          : OverlayImage(path: path, fit: BoxFit.contain),
                    ),
                  );
                },
              );
              }),
            ),
            ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBgPicker(BuildContext context, DashboardTheme theme) {
    return Container(
      decoration: const BoxDecoration(
        color: Win95.gray,
        border: Border(
          right: BorderSide(color: Win95.veryDark, width: 2),
          top: BorderSide(color: Win95.white, width: 2),
        ),
        boxShadow: [BoxShadow(color: Color(0x44000000), blurRadius: 10, offset: Offset(4, 0))],
      ),
      child: Column(
        children: [
          Win95TitleBar(
            title: 'Background',
            titleFontSize: 12,
            height: 32,
            buttonSize: 22,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            onClose: () =>
                ref.read(bgPickerOpenProvider.notifier).state = false,
          ),
          // Colors section
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Align(alignment: Alignment.centerLeft, child: Text('Colors', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black54))),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: themePalette.map((color) {
                return GestureDetector(
                  onTap: () => ref.read(themeProvider.notifier).state = DashboardTheme(color),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Win95.darkGray),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          // Images section
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 12, 8, 4),
            child: Align(alignment: Alignment.centerLeft, child: Text('Images', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black54))),
          ),
          // YouTube videos section
          if (youtubeBackgrounds.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 12, 8, 4),
              child: Align(alignment: Alignment.centerLeft, child: Text('Videos', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black54))),
            ),
            ...youtubeBackgrounds.map((yt) => GestureDetector(
              onTap: () => ref.read(themeProvider.notifier).setYouTubeBackground(yt),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  border: Border.all(color: Win95.darkGray),
                  borderRadius: BorderRadius.circular(4),
                  color: const Color(0xFFE0E0E0),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.play_circle_fill, size: 24, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(child: Text(yt.title, style: const TextStyle(fontSize: 11, color: Colors.black87), overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
            )),
          ],
          // Images section
          Expanded(
            child: FutureBuilder<List<String>>(
              future: getBackgroundImages(),
              builder: (context, snapshot) {
                final images = snapshot.data ?? [];
                if (images.isEmpty) return const Center(child: Text('No images', style: TextStyle(color: Colors.black54)));
                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: images.length,
                  itemBuilder: (_, i) {
                    final path = images[i];
                    final name = path.split(RegExp(r'[/\\]')).last;
                    return GestureDetector(
                      onTap: () => ref.read(themeProvider.notifier).state = DashboardTheme(randomAccent(), backgroundImage: path),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          border: Border.all(color: Win95.darkGray),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: Image.file(File(path), width: 48, height: 36, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 48, height: 36)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(name, style: const TextStyle(fontSize: 11, color: Colors.black87), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarouselView(BuildContext context) {
    final theme = ref.watch(themeProvider);
    return Column(
      key: const ValueKey('carousel'),
      children: [
        const SizedBox(height: 20),
        Expanded(
          child: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                // physics left as default — sticker drags are handled by GestureDetector on each sticker
                onPageChanged: (i) => setState(() => _currentPage = i % _cards.length),
                itemBuilder: (context, index) {
                  final cardIndex = index % _cards.length;
                  final card = _cards[cardIndex];
                  final isActive = cardIndex == _currentPage;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 140, vertical: 24),
                    child: DashboardCard(
                      title: card.title,
                      icon: card.icon,
                      onTap: isActive ? () => _openFullScreen(context, card.fullScreenBuilder()) : () {},
                      chromeOpacity: card.chromeOpacity,
                      child: card.cardBuilder(),
                    ),
                  );
                },
              ),
              // Nav arrows moved to outer Stack so they sit above stickers
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildGridView(BuildContext context) {
    // Split cards into two rows. Top row gets the extra card when N is odd,
    // so 5 cards → 3 on top, 2 on bottom.
    final n = _cards.length;
    final topCount = (n + 1) ~/ 2;
    final topCards = _cards.sublist(0, topCount);
    final bottomCards = _cards.sublist(topCount);
    return Padding(
      key: const ValueKey('grid'),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(flex: 2, child: Row(children: _gridRow(context, topCards))),
          const SizedBox(height: 12),
          if (bottomCards.isNotEmpty)
            Expanded(flex: 2, child: Row(children: _gridRow(context, bottomCards))),
        ],
      ),
    );
  }

  List<Widget> _gridRow(BuildContext context, List<_CardDef> cards) {
    final widgets = <Widget>[];
    for (int i = 0; i < cards.length; i++) {
      if (i > 0) widgets.add(const SizedBox(width: 12));
      final c = cards[i];
      widgets.add(Expanded(
        child: DashboardCard(
          title: c.title,
          icon: c.icon,
          onTap: () => _openFullScreen(context, c.fullScreenBuilder()),
          chromeOpacity: c.chromeOpacity,
          child: c.cardBuilder(),
        ),
      ));
    }
    return widgets;
  }
}

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: const Color(0x66000000),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: Icon(icon, size: 28, color: Colors.white),
      ),
    );
  }
}
