import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

/// A single decorative image placed on the dashboard canvas. Coordinates
/// are fractional — `x` is in `[0, numCards]` (lets graphics tile across
/// multiple card pages), `y` is in `[0, 1]`. `size` is in logical pixels,
/// `rotation` is degrees. Sparkles use `size == 0` as a sentinel — they
/// render at a fixed size set by the sparkle layer.
class PlacedOverlay {
  final String path;
  double x, y;
  double size;
  double rotation;
  PlacedOverlay(this.path, this.x, this.y, this.size, this.rotation);
}

/// File-system + randomizer helpers for the sparkle and graphics overlay
/// layers on the dashboard. Pure — no Flutter, no Riverpod, no state.
/// The caller drives provider updates and `mounted` checks.
class OverlayService {
  OverlayService._();

  /// Returns every image file (`.png` / `.apng` / `.jpg` / `.gif` /
  /// `.webp`) directly inside [dirPath], non-recursive. Missing
  /// directory returns `[]` rather than throwing.
  static Future<List<String>> listImageFiles(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];
    final files = <String>[];
    await for (final f in dir.list()) {
      final ext = f.path.toLowerCase();
      if (ext.endsWith('.png') ||
          ext.endsWith('.apng') ||
          ext.endsWith('.jpg') ||
          ext.endsWith('.gif') ||
          ext.endsWith('.webp')) {
        files.add(f.path);
      }
    }
    return files;
  }

  /// Generates the graphics-layer sticker layout across [numCards] tiled
  /// card pages. Positions are picked from a hand-tuned pattern that
  /// avoids the center (where the month/year title lives); each sticker
  /// gets a small random jitter, and stickers that land too close to
  /// each other are skipped. Returns the full list in a single pass —
  /// graphics don't need the batched streaming that sparkles do.
  ///
  /// [perCardCap] caps the number of stickers per card-page (default 40 =
  /// the size of the base position pattern). Lowering this shrinks both
  /// peak decoded-image memory and per-frame paint cost roughly linearly.
  static List<PlacedOverlay> generateGraphics(
    List<String> graphicFiles,
    int numCards, {
    int perCardCap = 40,
  }) {
    if (graphicFiles.isEmpty || perCardCap <= 0) return const [];
    final rng = math.Random();

    // Base positions for ONE screen — fractional x in [0, 1], y in [0, 1].
    // The pattern hugs the edges and skips the top-center band (x 0.15–0.80,
    // y < 0.12) where the month/year title sits.
    final basePositions = <List<double>>[
      // Top row — edges only
      [0.00, 0.00], [0.06, 0.00], [0.12, 0.00],
      [0.80, 0.00], [0.86, 0.00], [0.92, 0.00],
      // Bottom row
      [0.00, 0.82], [0.08, 0.82], [0.16, 0.82],
      [0.72, 0.82], [0.80, 0.82], [0.88, 0.82],
      [0.04, 0.90], [0.20, 0.90], [0.76, 0.90], [0.92, 0.90],
      // Left column
      [0.00, 0.12], [0.00, 0.24], [0.00, 0.36],
      [0.00, 0.48], [0.00, 0.60], [0.00, 0.72],
      [0.05, 0.18], [0.05, 0.42], [0.05, 0.66],
      // Right column
      [0.84, 0.12], [0.84, 0.24], [0.84, 0.36],
      [0.84, 0.48], [0.84, 0.60], [0.84, 0.72],
      [0.90, 0.18], [0.90, 0.42], [0.90, 0.66],
      // Inner — skip top-center band (y < 0.12 and x 0.15–0.80)
      [0.12, 0.14], [0.72, 0.14],
      [0.12, 0.22], [0.74, 0.22],
      [0.10, 0.30], [0.74, 0.30],
      [0.10, 0.40], [0.78, 0.40],
      [0.10, 0.50], [0.78, 0.50],
      [0.10, 0.60], [0.78, 0.60],
      [0.12, 0.68], [0.74, 0.68],
      [0.22, 0.20], [0.66, 0.20],
      [0.22, 0.70], [0.66, 0.70],
      [0.28, 0.75], [0.60, 0.75],
      [0.30, 0.15], [0.58, 0.15],
    ];

    // Tile positions across all card screens — each card-page gets its
    // own copy of the base pattern, shifted right by `card` whole x-units.
    final allPositions = <List<double>>[];
    for (int card = 0; card < numCards; card++) {
      for (final pos in basePositions) {
        allPositions.add([pos[0] + card.toDouble(), pos[1]]);
      }
    }
    allPositions.shuffle(rng);

    final count = math.min(allPositions.length, numCards * perCardCap);
    final shuffledFiles = List<String>.from(graphicFiles)..shuffle(rng);
    final usedPositions = <List<double>>[];
    final graphics = <PlacedOverlay>[];
    for (int i = 0; i < count && i < allPositions.length; i++) {
      final pos = allPositions[i];
      final jx = pos[0] + (rng.nextDouble() - 0.5) * 0.08;
      final jy = pos[1] + (rng.nextDouble() - 0.5) * 0.08;
      final tooClose = usedPositions.any((used) {
        final dx = (jx - used[0]).abs();
        final dy = (jy - used[1]).abs();
        return dx < 0.04 && dy < 0.04;
      });
      if (tooClose) continue;
      usedPositions.add([jx, jy]);
      graphics.add(PlacedOverlay(
        shuffledFiles[graphics.length % shuffledFiles.length],
        jx,
        jy,
        120 + rng.nextDouble() * 100, // 120–220 px, varied sizes
        (rng.nextDouble() - 0.5) * 30,
      ));
    }
    return graphics;
  }

  /// Generates [targetCount] sparkles in batches of 50, yielding the
  /// cumulative list after each batch. Callers await-for to progressively
  /// push batches into the sparkle provider so the UI doesn't freeze
  /// under the full allocation cost. The returned stream emits once per
  /// batch; terminates when the quota is reached.
  ///
  /// A [targetCount] of 0 returns immediately — handy when the sparkle
  /// quality is set to off.
  static Stream<List<PlacedOverlay>> generateSparkleBatches(
    List<String> sparkleFiles, {
    int targetCount = 350,
    Duration delayBetweenBatches = const Duration(milliseconds: 100),
  }) async* {
    if (sparkleFiles.isEmpty || targetCount <= 0) return;
    final rng = math.Random();
    const batchSize = 50;
    final all = <PlacedOverlay>[];

    for (int i = 0; i < targetCount; i += batchSize) {
      final count = (i + batchSize > targetCount) ? targetCount - i : batchSize;
      for (int j = 0; j < count; j++) {
        all.add(PlacedOverlay(
          sparkleFiles[rng.nextInt(sparkleFiles.length)],
          rng.nextDouble(),
          rng.nextDouble(),
          0,
          rng.nextDouble() * 360,
        ));
      }
      yield List.from(all);
      await Future.delayed(delayBetweenBatches);
    }
  }
}
