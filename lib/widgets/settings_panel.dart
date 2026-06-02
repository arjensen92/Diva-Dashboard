import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/effects_quality.dart';
import 'win95.dart';

/// Drawer panel showing per-effect quality controls. Mirrors the chrome
/// of the background picker panel — same Win95 title bar, same edge bevels.
///
/// Three effects are exposed: sparkles (the scattered background dots),
/// stickers (the per-card graphic + Gachamon overlays), and the YouTube
/// video background. Each maps to an [EffectQuality] tier (off/low/med/max)
/// with semantics defined in `effects_quality.dart`.
class SettingsPanel extends ConsumerWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: const BoxDecoration(
        color: Win95.gray,
        border: Border(
          right: BorderSide(color: Win95.veryDark, width: 2),
          top: BorderSide(color: Win95.white, width: 2),
        ),
        boxShadow: [
          BoxShadow(color: Color(0x44000000), blurRadius: 10, offset: Offset(4, 0))
        ],
      ),
      child: Column(
        children: [
          Win95TitleBar(
            title: 'Settings',
            titleFontSize: 12,
            height: 32,
            buttonSize: 22,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            onClose: () =>
                ref.read(settingsPanelOpenProvider.notifier).state = false,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 12, 10, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Effects Quality',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
              ),
            ),
          ),
          _QualityRow(
            label: 'Sparkles',
            description: 'Scattered glitter overlays',
            provider: sparkleQualityProvider,
          ),
          _QualityRow(
            label: 'Stickers',
            description: 'Card-page graphic decorations',
            provider: stickerQualityProvider,
          ),
          _BoolRow(
            label: 'Video Backgrounds',
            description: 'Animated YouTube backgrounds',
            provider: videoBackgroundEnabledProvider,
          ),
          const Spacer(),
          // Footer hint — quietly explains the memory tradeoff.
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Text(
              'Lower tiers use less memory and CPU. Off skips the effect entirely.',
              style: TextStyle(
                fontSize: 10,
                color: Colors.black54,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One labelled row with a 4-segment Win95-bevel pick list.
class _QualityRow extends ConsumerWidget {
  final String label;
  final String description;
  final StateProvider<EffectQuality> provider;

  const _QualityRow({
    required this.label,
    required this.description,
    required this.provider,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(provider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            description,
            style: const TextStyle(fontSize: 10, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final q in EffectQuality.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _QualityButton(
                      label: q.label,
                      selected: q == current,
                      onTap: () =>
                          ref.read(provider.notifier).state = q,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Same row chrome as [_QualityRow] but with a 2-segment On/Off toggle
/// instead of a 4-segment quality picker — used for effects whose state
/// is meaningfully binary (the WebView is either running or it isn't).
class _BoolRow extends ConsumerWidget {
  final String label;
  final String description;
  final StateProvider<bool> provider;

  const _BoolRow({
    required this.label,
    required this.description,
    required this.provider,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(provider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            description,
            style: const TextStyle(fontSize: 10, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _QualityButton(
                    label: 'Off',
                    selected: !on,
                    onTap: () => ref.read(provider.notifier).state = false,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _QualityButton(
                    label: 'On',
                    selected: on,
                    onTap: () => ref.read(provider.notifier).state = true,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pressable Win95-bevel quality button; shows the "pressed" bevel when
/// selected so the active tier reads as latched-down on the panel.
class _QualityButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _QualityButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Win95Button(
      pressed: selected,
      onTap: onTap,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: Colors.black,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
