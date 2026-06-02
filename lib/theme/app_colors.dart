import 'package:flutter/material.dart';

/// Dashboard-wide color tokens + a couple of layout constants (corner
/// radii, minimum tap target). Semantic names (`bg`, `surface`, `accent`,
/// `textMuted`) — UI code should reach for these rather than hex literals.
///
/// Win95 chrome colors live in [Win95] (lib/widgets/win95.dart), NOT here.
class AppColors {
  static const bg = Color(0xFF0F1117);
  static const surface = Color(0xFF1A1D27);
  static const surfaceHover = Color(0xFF232734);
  static const border = Color(0xFF2A2E3A);
  static const text = Color(0xFFE4E6EF);
  static const textMuted = Color(0xFF8B8FA3);
  static const accent = Color(0xFF6366F1);
  static const accentGlow = Color(0x266366F1);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const orange = Color(0xFFF59E0B);
  static const pink = Color(0xFFEC4899);
  static const cyan = Color(0xFF06B6D4);
  static const purple = Color(0xFF8B5CF6);

  static const double radius = 16.0;
  static const double radiusSm = 10.0;
  static const double minTapTarget = 44.0;

  static const List<Color> habitColors = [
    accent, green, orange, red, pink, cyan, purple,
  ];

  /// Drop shadow for text readability on pastel/image backgrounds
  static const List<Shadow> textShadow = [
    Shadow(color: Color(0x55000000), blurRadius: 4, offset: Offset(1, 1)),
  ];

  static const List<Shadow> textShadowStrong = [
    Shadow(color: Color(0x88000000), blurRadius: 6, offset: Offset(1, 2)),
  ];
}
