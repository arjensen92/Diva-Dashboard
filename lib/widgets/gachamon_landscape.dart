import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../gachamon/gachamon_data.dart';
import '../services/gachamon_game_service.dart';

/// A procedurally generated landscape — sky/ground gradient + the user's
/// caught gachamon placed at pseudo-random but stable positions.
class GachamonLandscape extends StatelessWidget {
  final List<String> caughtKeys;
  const GachamonLandscape({super.key, required this.caughtKeys});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: LayoutBuilder(builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return Stack(
          children: [
            // Sky → grass gradient backdrop
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF87CEEB), // sky blue
                    Color(0xFFAEE0FF), // pale sky
                    Color(0xFF9CD67D), // light grass
                    Color(0xFF5CAE43), // grass
                  ],
                  stops: [0.0, 0.45, 0.55, 1.0],
                ),
              ),
            ),
            // A few puffy clouds
            for (int i = 0; i < 3; i++)
              Positioned(
                left: w * (0.08 + i * 0.34) - 30,
                top: h * (0.06 + (i % 2) * 0.08),
                child: _Cloud(width: 60 + (i * 8).toDouble()),
              ),
            // Caught gachamon — uniform sprite boxes standing on the grass.
            // Feet are anchored to a y-line within the grass strip; the
            // sprite's contain-fit handles tall/short gachamon naturally.
            ...caughtKeys.asMap().entries.map((entry) {
              final pk = gachamonByKey(entry.value);
              if (pk == null) return const SizedBox.shrink();
              final pos = _positionFor(entry.value.hashCode, entry.key);
              const size = 60.0;
              // Grass band starts at ~0.55h. Give sprites a small vertical
              // jitter inside it so rows don't look ruler-straight.
              final feetY = 0.62 * h + pos.dy * (h * 0.30);
              final top = (feetY - size).clamp(0.0, h - size);
              final left = pos.dx * (w - size);
              return Positioned(
                left: left,
                top: top,
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Image.file(
                    File(gachamonSpritePath(pk)),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              );
            }),
          ],
        );
      }),
    );
  }

  /// Stable pseudo-random position per catch (seed = unique-key hash ⊕ slot),
  /// so repositioning is consistent across rebuilds but duplicate catches of
  /// the same gachamon don't perfectly overlap.
  Offset _positionFor(int seed, int slot) {
    final rng = math.Random(seed * 2654435761 ^ slot);
    return Offset(rng.nextDouble(), rng.nextDouble());
  }
}

class _Cloud extends StatelessWidget {
  final double width;
  const _Cloud({required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: width * 0.45,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(width),
      ),
    );
  }
}
