import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/effects_quality.dart';
import '../screens/dashboard_screen.dart';

/// Renders an image file
class OverlayImage extends StatelessWidget {
  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;

  const OverlayImage({super.key, required this.path, this.width, this.height, this.fit = BoxFit.contain});

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(path),
      width: width,
      height: height,
      fit: fit,
      gaplessPlayback: true,
      isAntiAlias: false,
      filterQuality: FilterQuality.none,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}

/// Renders all sparkle images with RepaintBoundary for performance.
/// Returns an empty box when sparkle quality is set to off, so the
/// Settings panel's quality tier disables all sparkles in one go.
class SparkleOverlay extends ConsumerWidget {
  const SparkleOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(sparkleQualityProvider) == EffectQuality.off) {
      return const SizedBox.shrink();
    }
    final sparkles = ref.watch(sparkleImagesProvider);
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;

    return IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          children: sparkles.map((s) => Positioned(
            left: s.x * screenW,
            top: s.y * screenH,
            child: RepaintBoundary(
              child: Transform.rotate(
                angle: s.rotation * math.pi / 180,
                child: Opacity(
                  opacity: 0.4,
                  child: OverlayImage(path: s.path),
                ),
              ),
            ),
          )).toList(),
        ),
      ),
    );
  }
}
