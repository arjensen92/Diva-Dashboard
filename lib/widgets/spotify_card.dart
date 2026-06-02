import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_colors.dart';
import '../providers/spotify_provider.dart';
import '../services/visualizer_service.dart';

const _spotifyGreen = Color(0xFF1DB954);

class SpotifyCardContent extends ConsumerWidget {
  const SpotifyCardContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(spotifyProvider);

    if (!state.connected) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_note, size: 40, color: AppColors.textMuted),
            SizedBox(height: 8),
            Text('Connect Spotify', style: TextStyle(color: AppColors.textMuted, shadows: AppColors.textShadow)),
          ],
        ),
      );
    }

    final track = state.track;
    if (track == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No track playing', style: TextStyle(color: AppColors.textMuted, shadows: AppColors.textShadow)),
            SizedBox(height: 4),
            Text('Play something on Spotify', style: TextStyle(color: AppColors.textMuted, fontSize: 12, shadows: AppColors.textShadow)),
          ],
        ),
      );
    }

    final albumArt = (track['album']?['images'] as List?)?.isNotEmpty == true
        ? track['album']['images'][0]['url']
        : null;
    final artists = (track['artists'] as List?)?.map((a) => a['name']).join(', ') ?? '';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Visualizer — slightly oversized so it hugs the card's sunken frame
        const Positioned(
          left: -7, right: -7, top: -7, bottom: -7,
          child: Opacity(
            opacity: 0.5,
            child: MiniVisualizer(height: double.infinity),
          ),
        ),
        // Content on top
        Column(
          children: [
            // Spinning CD album art
            Expanded(
              child: Center(
                child: _SpinningCD(
                  albumArt: albumArt,
                  isPlaying: state.isPlaying,
                ),
              ),
            ),
            // Track info
            const SizedBox(height: 8),
            Text(
              track['name'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, shadows: AppColors.textShadow),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              artists,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13, shadows: AppColors.textShadow),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            // Controls with dark background
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppColors.radius),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () => ref.read(spotifyProvider.notifier).previous(),
                    icon: const Icon(Icons.skip_previous, size: 28, color: Colors.white),
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 48, height: 48,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: _spotifyGreen),
                    child: IconButton(
                      onPressed: () => state.isPlaying
                          ? ref.read(spotifyProvider.notifier).pause()
                          : ref.read(spotifyProvider.notifier).play(),
                      icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow, size: 26, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () => ref.read(spotifyProvider.notifier).next(),
                    icon: const Icon(Icons.skip_next, size: 28, color: Colors.white),
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Circular CD-shaped album art that spins when playing
class _SpinningCD extends StatefulWidget {
  final String? albumArt;
  final bool isPlaying;

  const _SpinningCD({this.albumArt, required this.isPlaying});

  @override
  State<_SpinningCD> createState() => _SpinningCDState();
}

class _SpinningCDState extends State<_SpinningCD> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.isPlaying) _controller.repeat();
  }

  @override
  void didUpdateWidget(_SpinningCD oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isPlaying && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = math.min(constraints.maxWidth, constraints.maxHeight) * 0.85;
      return AnimatedBuilder(
        animation: _controller,
        builder: (_, child) => Transform.rotate(
          angle: _controller.value * 2 * math.pi,
          child: child,
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Data ring — album art as an annulus (hub is ~44% of diameter)
              ClipPath(
                clipper: _CDClipper(holeRatio: 0.24),
                child: ClipOval(
                  child: widget.albumArt != null
                      ? Image.network(widget.albumArt!, width: size, height: size, fit: BoxFit.cover)
                      : Container(
                          width: size, height: size,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [Colors.grey.shade800, Colors.grey.shade600, Colors.grey.shade800],
                              stops: const [0.0, 0.5, 1.0],
                            ),
                          ),
                        ),
                ),
              ),
              // Iridescent sheen overlay on the data ring
              ClipPath(
                clipper: _CDClipper(holeRatio: 0.24),
                child: Container(
                  width: size,
                  height: size,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        Color(0x33FF8AD8), // pink
                        Color(0x3380C7FF), // blue
                        Color(0x338AFFB0), // green
                        Color(0x33FFE58A), // yellow
                        Color(0x33FF8AD8), // back to pink
                      ],
                      stops: [0.0, 0.3, 0.55, 0.8, 1.0],
                    ),
                  ),
                ),
              ),
              // Black ring — no fill, transparent center shows the card behind
              Container(
                width: size * 0.28,
                height: size * 0.28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: size * 0.025),
                ),
              ),
              // Dark gray ring — sits just inside the black ring, unfilled
              Container(
                width: size * 0.215,
                height: size * 0.215,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade800, width: 1.5),
                ),
              ),
              // Hub annulus — semi-transparent white, extends from the inner
              // edge of the black ring (diameter 0.23) to the outer edge of
              // the innermost ring (diameter 0.10). Thickness = 0.065.
              Container(
                width: size * 0.23,
                height: size * 0.23,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                    width: size * 0.065,
                  ),
                ),
              ),
              // Innermost gray ring — stroke only, fully transparent center
              Container(
                width: size * 0.10,
                height: size * 0.10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade700, width: 1.5),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// Clips a circle with a hole in the center — like a CD
class _CDClipper extends CustomClipper<Path> {
  final double holeRatio;
  _CDClipper({this.holeRatio = 0.18});

  @override
  Path getClip(Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final innerRadius = outerRadius * holeRatio;

    final path = Path()
      ..addOval(Rect.fromCircle(center: center, radius: outerRadius))
      ..addOval(Rect.fromCircle(center: center, radius: innerRadius))
      ..fillType = PathFillType.evenOdd;

    return path;
  }

  @override
  bool shouldReclip(covariant _CDClipper oldClipper) => oldClipper.holeRatio != holeRatio;
}
