import 'package:flutter/material.dart';

/// Spacing scale on the 4dp grid; margins are [md] on compact and [lg] on
/// medium windows and up.
abstract final class AppSpacing {
  /// Extra small step (4dp), for tight gaps between related elements.
  static const double xs = 4;

  /// Small step (8dp), the base layout unit.
  static const double sm = 8;

  /// Medium step (16dp), the margin on compact windows.
  static const double md = 16;

  /// Large step (24dp), the margin on medium windows and up.
  static const double lg = 24;
}

/// Shape tokens (M3 shape scale) read by the component themes.
abstract final class AppRadii {
  /// Small corner radius (8dp), used by chips.
  static const double small = 8;

  /// Medium corner radius (12dp), used by cards.
  static const double medium = 12;

  /// Large corner radius (16dp), used by sheets and large surfaces.
  static const double large = 16;

  /// Extra large corner radius (28dp), used by dialogs.
  static const double extraLarge = 28;
}

/// M3 light and dark themes built from the brand seed.
abstract final class AppTheme {
  static const Color _seed = Color(0xFF6750A4);

  /// The light theme.
  static ThemeData light() => _build(Brightness.light);

  /// The dark theme.
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.medium),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHigh,
        elevation: 0,
        shape: cardShape,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        selectedColor: colorScheme.primaryContainer,
        labelStyle: TextStyle(color: colorScheme.onSurface),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant),
    );
  }
}
