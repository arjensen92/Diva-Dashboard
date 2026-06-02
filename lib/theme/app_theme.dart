import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Material [ThemeData] factory for the dashboard. Only a dark theme —
/// the app runs fullscreen on a kitchen kiosk, light mode isn't a use
/// case. Pulls all colors from [AppColors] so palette tweaks stay
/// centralized.
class AppTheme {
  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.surface,
      cardColor: AppColors.surface,
      primaryColor: AppColors.accent,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        secondary: AppColors.accent,
        surface: AppColors.surface,
        error: AppColors.red,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.text,
        onError: Colors.white,
      ),
      fontFamily: 'Segoe UI',
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: AppColors.text, fontSize: 16, shadows: AppColors.textShadow),
        bodyMedium: TextStyle(color: AppColors.text, fontSize: 15, shadows: AppColors.textShadow),
        bodySmall: TextStyle(color: AppColors.textMuted, fontSize: 13, shadows: AppColors.textShadow),
        titleLarge: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w700, shadows: AppColors.textShadowStrong),
        titleMedium: TextStyle(color: AppColors.textMuted, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.5, shadows: AppColors.textShadow),
        labelLarge: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w600, shadows: AppColors.textShadow),
      ),
      dividerColor: AppColors.border,
      iconTheme: const IconThemeData(color: AppColors.text),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusSm),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusSm),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusSm),
          borderSide: const BorderSide(color: AppColors.accent, width: 2),
        ),
        labelStyle: const TextStyle(color: AppColors.textMuted),
        hintStyle: const TextStyle(color: AppColors.textMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(AppColors.minTapTarget, AppColors.minTapTarget),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.radiusSm)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          side: const BorderSide(color: AppColors.border),
          minimumSize: const Size(AppColors.minTapTarget, AppColors.minTapTarget),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.radiusSm)),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.accent,
        thumbColor: AppColors.accent,
        inactiveTrackColor: AppColors.border,
        trackHeight: 6,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 12),
      ),
    );
  }
}
