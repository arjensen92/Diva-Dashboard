import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'theme/app_theme.dart';
import 'screens/dashboard_screen.dart';
import 'database/database.dart';
import 'providers/effects_quality.dart';
import 'services/env_service.dart';
import 'services/video_background_service.dart';
import 'services/gachadex_service.dart';
import 'widgets/youtube_background.dart';

final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from .env file on disk
  await Env.load();

  // Load YouTube video backgrounds from video_backgrounds.json (auto-enriches
  // from the YouTube Data API if any entries are missing title/duration)
  await VideoBackgroundService.load();

  // Load the Gachadex from gachadex.json (written as a seed on first run)
  await GachadexService.load();

  // Setup window for fullscreen tablet experience
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    minimumSize: Size(800, 600),
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
    skipTaskbar: false,
  );
  // Flip to `true` during development to preview the dashboard in a
  // Surface-tablet-sized window (1920×1280, centered on the primary
  // display). Leave `false` for production — the app goes fake-fullscreen
  // on the preferred display (see [_preferredDisplay]).
  const previewTablet = false;

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    if (previewTablet) {
      // Preview at Surface tablet resolution (1920x1280)
      await windowManager.setSize(const Size(1920, 1280));
      await windowManager.center();
    } else {
      // Fake fullscreen: borderless window sized to the target monitor's full
      // resolution. Prefers the secondary monitor. Avoids setFullScreen(true)
      // because exclusive fullscreen binds the window to one display and
      // blocks Win+Shift+Left/Right cross-monitor moves.
      final target = await _preferredDisplay();
      if (target != null) {
        final origin = target.visiblePosition ?? Offset.zero;
        await windowManager.setPosition(origin);
        await Future.delayed(const Duration(milliseconds: 60));
        await windowManager.setSize(target.size);
      } else {
        await windowManager.maximize();
      }
    }
    await windowManager.show();
    await windowManager.focus();
  });

  // When Windows moves the window across monitors (Win+Shift+Left/Right),
  // exclusive fullscreen stays bound to the old monitor and the app becomes
  // invisible. Re-engaging fullscreen on the move event rebinds it to the
  // monitor the window is now on.
  windowManager.addListener(_MonitorFollowListener());

  runApp(const ProviderScope(child: KitchenDashboardApp()));
}

/// Returns the preferred Display for the kitchen dashboard — a non-primary
/// display when available (i.e. the secondary monitor), otherwise the primary.
/// Returns null only if display enumeration itself fails.
Future<Display?> _preferredDisplay() async {
  try {
    final primary = await screenRetriever.getPrimaryDisplay();
    final all = await screenRetriever.getAllDisplays();
    final target = all.firstWhere(
      (d) => d.id != primary.id,
      orElse: () => primary,
    );
    print('[Window] Launching on display "${target.name}" '
        '(${target.size.width.toInt()}x${target.size.height.toInt()} @ ${target.visiblePosition})');
    return target;
  } catch (e) {
    print('[Window] Display enumeration failed: $e');
    return null;
  }
}

class _MonitorFollowListener with WindowListener {
  bool _rebinding = false;

  @override
  void onWindowMoved() async {
    if (_rebinding) return;
    if (!await windowManager.isFullScreen()) return;
    _rebinding = true;
    try {
      await windowManager.setFullScreen(false);
      await Future.delayed(const Duration(milliseconds: 60));
      await windowManager.setFullScreen(true);
    } finally {
      _rebinding = false;
    }
  }
}

class KitchenDashboardApp extends StatelessWidget {
  const KitchenDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kitchen Dashboard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const DashboardScreen(),
      // Render the YouTube video background beneath the Navigator so it keeps
      // playing uninterrupted when a full-view route is pushed on top.
      builder: (context, child) => Consumer(
        builder: (context, ref, _) {
          final theme = ref.watch(themeProvider);
          // The YouTube background is the heaviest single source of
          // memory + CPU in the app — gate it on the on/off toggle so
          // users can drop it when the dashboard's been running long
          // enough to feel sluggish.
          final videoBgEnabled = ref.watch(videoBackgroundEnabledProvider);
          return Stack(
            children: [
              if (videoBgEnabled && theme.youtubeBackground != null)
                Positioned.fill(
                  child: YouTubeBackgroundPlayer(
                    key: ValueKey('ytbg_${theme.youtubeBackground!.videoId}_${theme.youtubeStartSeconds}'),
                    videoId: theme.youtubeBackground!.videoId,
                    startSeconds: theme.youtubeStartSeconds ?? 0,
                    videoAspectRatio: theme.youtubeBackground!.aspectRatio,
                  ),
                ),
              if (child != null) child,
            ],
          );
        },
      ),
    );
  }
}
