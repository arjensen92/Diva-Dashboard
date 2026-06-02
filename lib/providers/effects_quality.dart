import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Granular quality tier for each visual effect. `off` disables the effect
/// entirely (zero memory cost); `low`/`med`/`max` increase counts/quality.
///
/// In-memory only — persisting across launches is intentionally NOT done so
/// users can experiment and the dashboard always boots in a known state.
enum EffectQuality { off, low, med, max }

/// How many sparkles to scatter across the background.
extension SparkleCount on EffectQuality {
  /// Total sparkle target. Sparkle generation tolerates a count of 0.
  int get sparkleCount {
    switch (this) {
      case EffectQuality.off:
        return 0;
      case EffectQuality.low:
        return 50;
      case EffectQuality.med:
        return 150;
      case EffectQuality.max:
        return 250;
    }
  }

  /// How many graphic stickers to place per card-page in the carousel.
  int get stickersPerCard {
    switch (this) {
      case EffectQuality.off:
        return 0;
      case EffectQuality.low:
        return 8;
      case EffectQuality.med:
        return 20;
      case EffectQuality.max:
        return 40;
    }
  }

  /// Short user-facing label for menu rows.
  String get label {
    switch (this) {
      case EffectQuality.off:
        return 'Off';
      case EffectQuality.low:
        return 'Low';
      case EffectQuality.med:
        return 'Med';
      case EffectQuality.max:
        return 'Max';
    }
  }
}

/// Quality of the random sparkle field across the dashboard background.
final sparkleQualityProvider =
    StateProvider<EffectQuality>((ref) => EffectQuality.max);

/// Quality of the per-card sticker overlays (graphics + Gachamon sprites).
final stickerQualityProvider =
    StateProvider<EffectQuality>((ref) => EffectQuality.max);

/// Whether the YouTube video background player runs at all. Controls
/// both the random theme shuffle (off keeps YT entries out of the pool)
/// and the live player widget (off removes it from the tree, disposing
/// the WebviewController and freeing its WebView2 process).
///
/// Modeled as a plain bool — the WebView is either running or it isn't,
/// so the 4-tier quality enum used by sparkles/stickers doesn't apply.
final videoBackgroundEnabledProvider =
    StateProvider<bool>((ref) => true);

/// Whether the Settings panel drawer is open.
final settingsPanelOpenProvider = StateProvider<bool>((ref) => false);
