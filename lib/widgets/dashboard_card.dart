import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'win95.dart';

class DashboardCard extends ConsumerWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final VoidCallback onTap;
  final int colSpan;

  /// Fades only the outer gray matte + inner white wash. The outer bevel
  /// border, title bar, and inner sunken border stay fully opaque.
  final double chromeOpacity;

  const DashboardCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    required this.onTap,
    this.colSpan = 1,
    this.chromeOpacity = 1.0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap,
      child: Win95Panel(
        fillOpacity: 0.85 * chromeOpacity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Win95TitleBar(
              title: title,
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              titleFontSize: 12,
              leading: Icon(icon, size: 14, color: Colors.white),
              onMinimize: () {},
              onMaximize: () {},
              onClose: onTap,
            ),
            Expanded(
              child: Win95InsetPanel(
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.all(8),
                fillOpacity: 0.15 * chromeOpacity,
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
