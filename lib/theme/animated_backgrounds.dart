import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/path_service.dart';
import '../services/video_background_service.dart';

/// The palette — one is picked randomly every hour and on boot
const List<Color> themePalette = [
  Color(0xFFF98284), // coral pink
  Color(0xFFB0A9E4), // lavender
  Color(0xFFACCCE4), // baby blue
  Color(0xFFB3E3DA), // mint
  Color(0xFFFEAAE4), // bubblegum pink
  Color(0xFFB0EB93), // lime green
  Color(0xFFE9F59D), // yellow-green
  Color(0xFFFFC384), // peach
  Color(0xFFFFF7A0), // butter yellow
  Color(0xFF8ACE00), // bright lime
];

/// YouTube video backgrounds — video ID + duration in seconds
class YouTubeBackground {
  final String videoId;
  final String title;
  final int durationSeconds;
  final double aspectRatio; // width/height — 16/9 = 1.778, 4/3 = 1.333
  const YouTubeBackground({required this.videoId, required this.title, required this.durationSeconds, this.aspectRatio = 16 / 9});
}

/// YouTube background videos — edit `video_backgrounds.json` at the project
/// root. Drop a URL in and the app fetches title + duration on next launch.
List<YouTubeBackground> get youtubeBackgrounds => VideoBackgroundService.videos;

/// Derive a full theme from a single accent color, background image, or YouTube video
class DashboardTheme {
  final Color accent;
  final String? backgroundImage;
  final YouTubeBackground? youtubeBackground;
  final int? youtubeStartSeconds; // random start position

  DashboardTheme(this.accent, {this.backgroundImage, this.youtubeBackground, this.youtubeStartSeconds});

  Color get surfaceColor => Colors.white.withValues(alpha: 0.15);
  Color get cardColor => Colors.white.withValues(alpha: 0.18);
  Color get borderColor => Colors.white.withValues(alpha: 0.35);
  Color get textColor => const Color(0xFF1A1A2E);
  Color get textMuted => const Color(0xFF444466);
  Color get particleColor => Colors.white;
}

/// Pick a random color from the palette
Color randomAccent() {
  return themePalette[math.Random().nextInt(themePalette.length)];
}

/// Get background image files from assets/backgrounds/
Future<List<String>> getBackgroundImages() async {
  final dir = Directory(PathService.backgroundsDir);
  if (!await dir.exists()) return [];
  final files = <String>[];
  await for (final f in dir.list()) {
    if (f is! File) continue;
    final ext = f.path.toLowerCase();
    if (ext.endsWith('.png') || ext.endsWith('.apng') || ext.endsWith('.jpg') || ext.endsWith('.jpeg') || ext.endsWith('.gif') || ext.endsWith('.webp')) {
      // Only files directly in backgrounds/, not in subfolders
      files.add(f.path);
    }
  }
  return files;
}

/// Background widget — solid color, image, or YouTube video
class AnimatedBackground extends StatelessWidget {
  final DashboardTheme theme;
  final Widget child;

  const AnimatedBackground({super.key, required this.theme, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (theme.youtubeBackground != null)
          const SizedBox.expand() // YouTube rendered at app level, not here
        else if (theme.backgroundImage != null)
          Image.file(
            File(theme.backgroundImage!),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => ColoredBox(color: theme.accent, child: const SizedBox.expand()),
          )
        else
          ColoredBox(color: theme.accent, child: const SizedBox.expand()),
        child,
      ],
    );
  }
}
