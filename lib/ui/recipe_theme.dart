import 'package:flutter/material.dart';

/// Shared palette for the approved cream / sage / forest-green direction.
abstract final class RecipeTheme {
  static const cream = Color(0xFFF7F5EE);
  static const forest = Color(0xFF365848);
  static const sage = Color(0xFFDCE6D9);
  static const ink = Color(0xFF273B32);
  static const outline = Color(0xFFD7DDD2);
  static const warning = Color(0xFF96361F);
  static const warningSurface = Color(0xFFF8E9DF);

  static ThemeData get light {
    final colors = ColorScheme.fromSeed(seedColor: forest).copyWith(
      primary: forest,
      onPrimary: Colors.white,
      primaryContainer: sage,
      onPrimaryContainer: forest,
      secondaryContainer: sage,
      onSecondaryContainer: forest,
      surface: cream,
      onSurface: ink,
      surfaceContainerLow: Colors.white,
      surfaceContainer: const Color(0xFFEEF1E9),
      surfaceContainerHighest: sage,
      outlineVariant: const Color(0xFFD7DDD2),
    );
    return ThemeData(
      colorScheme: colors,
      scaffoldBackgroundColor: cream,
      fontFamily: 'sans-serif',
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: cream,
        foregroundColor: forest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: forest, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.error, width: 2),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cream,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: cream,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        dragHandleColor: forest,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: sage,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: const StadiumBorder()),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
      ),
    );
  }
}
