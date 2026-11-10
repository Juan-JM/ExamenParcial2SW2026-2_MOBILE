import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Paleta y tema de la app: neutros cálidos (zinc), un solo acento índigo y
/// verde solo para "en vivo". Mismo lenguaje visual que la vista web.
class AppColors {
  static const ink = Color(0xFF18181B);
  static const text = Color(0xFF27272A);
  static const muted = Color(0xFF71717A);
  static const subtle = Color(0xFFA1A1AA);
  static const line = Color(0xFFE4E4E7);
  static const surface = Color(0xFFFFFFFF);
  static const background = Color(0xFFF7F7F8);
  static const soft = Color(0xFFF1F1F3);
  static const accent = Color(0xFF4F46E5);
  static const accentSoft = Color(0xFFEEF0FF);
  static const live = Color(0xFF10B981);
  static const liveSoft = Color(0xFFE7F8F1);
  static const danger = Color(0xFFDC2626);
  static const dangerSoft = Color(0xFFFDECEC);
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.accent,
      onPrimary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      error: AppColors.danger,
      outline: AppColors.line,
      outlineVariant: AppColors.line,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final text = base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.ink);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      textTheme: text.copyWith(
        headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.6),
        headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.3),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.1),
        bodyMedium: text.bodyMedium?.copyWith(color: AppColors.text, height: 1.35),
        bodySmall: text.bodySmall?.copyWith(color: AppColors.muted),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: AppColors.surface,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: const TextStyle(color: AppColors.subtle),
        labelStyle: const TextStyle(color: AppColors.muted),
        prefixIconColor: AppColors.subtle,
        border: _border(AppColors.line),
        enabledBorder: _border(AppColors.line),
        focusedBorder: _border(AppColors.accent, width: 1.6),
        errorBorder: _border(AppColors.danger),
        focusedErrorBorder: _border(AppColors.danger, width: 1.6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.ink.withValues(alpha: 0.5),
          disabledForegroundColor: Colors.white70,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.line),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.accentSoft,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? AppColors.ink : AppColors.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? AppColors.accent : AppColors.muted,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.accent),
    );
  }

  static OutlineInputBorder _border(Color color, {double width = 1}) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: color, width: width),
  );
}
