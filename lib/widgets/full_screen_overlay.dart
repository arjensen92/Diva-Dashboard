import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/animated_backgrounds.dart';
import '../screens/dashboard_screen.dart';
import 'sparkle_overlay.dart';
import 'win95.dart';

/// Chrome shared by every full-screen "app" route — title bar, animated
/// background matching the current dashboard theme, and a sparkle overlay.
/// Pushed via [ZoomInRoute] or [SlideUpRoute] from the dashboard tiles.
class FullScreenOverlay extends ConsumerWidget {
  final String title;
  final Widget child;

  /// When true (default) the [child] is wrapped in a SingleChildScrollView
  /// with 20 px padding. Set to false when the child needs to manage its
  /// own scrolling (e.g. a pinned header + inner scrollable area, like
  /// GachamonFullScreen's status bar that stays visible while the gachadex
  /// grid scrolls underneath).
  final bool scrollable;

  const FullScreenOverlay({
    super.key,
    required this.title,
    required this.child,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBackground(
        theme: theme,
        child: Stack(
          children: [
            const SparkleOverlay(),
            Column(
              children: [
                Win95TitleBar(
                  title: title,
                  titleFontSize: 16,
                  buttonSize: 44,
                  // Extra top padding so the min/max/close buttons have
                  // breathing room under the top edge of the title bar.
                  padding: const EdgeInsets.fromLTRB(6, 12, 6, 4),
                  onMinimize: () {},
                  onMaximize: () {},
                  onClose: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: scrollable
                      ? SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.all(20),
                          child: child,
                        )
                      : child,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ZoomInRoute extends PageRouteBuilder {
  final Widget page;
  ZoomInRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
            final fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: const Interval(0.0, 0.6, curve: Curves.easeOut)),
            );
            return FadeTransition(opacity: fadeAnimation, child: ScaleTransition(scale: scaleAnimation, child: child));
          },
          transitionDuration: const Duration(milliseconds: 350),
          reverseTransitionDuration: const Duration(milliseconds: 250),
        );
}

class SlideUpRoute extends PageRouteBuilder {
  final Widget page;
  SlideUpRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final tween = Tween(begin: const Offset(0, 1), end: Offset.zero).chain(CurveTween(curve: Curves.easeOut));
            return SlideTransition(position: animation.drive(tween), child: child);
          },
          transitionDuration: const Duration(milliseconds: 250),
        );
}
