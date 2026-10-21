import 'package:cutter/app/theme/app_tokens.dart';
import 'package:flutter/material.dart';

const ColorScheme _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF6750A4),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFEADDFF),
  onPrimaryContainer: Color(0xFF21005D),
  secondary: Color(0xFF625B71),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFE8DEF8),
  onSecondaryContainer: Color(0xFF1D192B),
  tertiary: Color(0xFF7D5260),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFFFD8E4),
  onTertiaryContainer: Color(0xFF31111D),
  error: Color(0xFFB3261E),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFF9DEDC),
  onErrorContainer: Color(0xFF410E0B),
  surface: Color(0xFFFEF7FF),
  onSurface: Color(0xFF1D1B20),
  onSurfaceVariant: Color(0xFF49454F),
  outline: Color(0xFF79747E),
  outlineVariant: Color(0xFFCAC4D0),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFF322F35),
  onInverseSurface: Color(0xFFF5EFF7),
  inversePrimary: Color(0xFFD0BCFF),
  surfaceTint: Color(0xFF6750A4),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF7F2FA),
  surfaceContainer: Color(0xFFF3EDF7),
  surfaceContainerHigh: Color(0xFFECE6F0),
  surfaceContainerHighest: Color(0xFFE6E0E9),
);

const ColorScheme _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFD0BCFF),
  onPrimary: Color(0xFF381E72),
  primaryContainer: Color(0xFF4F378B),
  onPrimaryContainer: Color(0xFFEADDFF),
  secondary: Color(0xFFCCC2DC),
  onSecondary: Color(0xFF332D41),
  secondaryContainer: Color(0xFF4A4458),
  onSecondaryContainer: Color(0xFFE8DEF8),
  tertiary: Color(0xFFEFB8C8),
  onTertiary: Color(0xFF492532),
  tertiaryContainer: Color(0xFF633B48),
  onTertiaryContainer: Color(0xFFFFD8E4),
  error: Color(0xFFF2B8B5),
  onError: Color(0xFF601410),
  errorContainer: Color(0xFF8C1D18),
  onErrorContainer: Color(0xFFF9DEDC),
  surface: Color(0xFF141218),
  onSurface: Color(0xFFE6E0E9),
  onSurfaceVariant: Color(0xFFCAC4D0),
  outline: Color(0xFF938F99),
  outlineVariant: Color(0xFF49454F),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFFE6E0E9),
  onInverseSurface: Color(0xFF322F35),
  inversePrimary: Color(0xFF6750A4),
  surfaceTint: Color(0xFFD0BCFF),
  surfaceContainerLowest: Color(0xFF0F0D13),
  surfaceContainerLow: Color(0xFF1D1B20),
  surfaceContainer: Color(0xFF211F26),
  surfaceContainerHigh: Color(0xFF2B2930),
  surfaceContainerHighest: Color(0xFF36343B),
);

/// Builds the light Material 3 theme from the DESIGN.md color roles.
ThemeData buildLightTheme() => _buildTheme(_lightScheme);

/// Builds the dark Material 3 theme from the DESIGN.md color roles.
ThemeData buildDarkTheme() => _buildTheme(_darkScheme);

ThemeData _buildTheme(ColorScheme scheme) {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
  );
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: _textTheme(base.textTheme),
    focusColor: scheme.primary.withValues(alpha: 0.12),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerHigh,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.medium)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(AppSizes.minTarget, AppSizes.minTarget),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(AppSizes.minTarget, AppSizes.minTarget),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(AppSizes.minTarget, AppSizes.minTarget),
        shape: const StadiumBorder(),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(AppSizes.minTarget, AppSizes.minTarget),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.extraLarge),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.extraSmall)),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.small)),
      ),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    dialogTheme: const DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.extraLarge)),
      ),
    ),
  );
}

TextTheme _textTheme(TextTheme base) {
  return base.copyWith(
    displayLarge: base.displayLarge?.copyWith(fontSize: 57, height: 64 / 57),
    displayMedium: base.displayMedium?.copyWith(fontSize: 45, height: 52 / 45),
    headlineLarge: base.headlineLarge?.copyWith(fontSize: 32, height: 40 / 32),
    headlineMedium:
        base.headlineMedium?.copyWith(fontSize: 28, height: 36 / 28),
    headlineSmall: base.headlineSmall?.copyWith(fontSize: 24, height: 32 / 24),
    titleLarge: base.titleLarge?.copyWith(fontSize: 22, height: 28 / 22),
    titleMedium: base.titleMedium?.copyWith(
      fontSize: 16,
      height: 24 / 16,
      fontWeight: FontWeight.w500,
    ),
    bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, height: 24 / 16),
    bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, height: 20 / 14),
    labelLarge: base.labelLarge?.copyWith(
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w500,
    ),
    labelMedium: base.labelMedium?.copyWith(
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w500,
    ),
  );
}
