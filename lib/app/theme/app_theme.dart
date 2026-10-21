import 'package:cutter/app/theme/seed_presets.dart';
import 'package:cutter/features/settings/domain/appearance_settings.dart';
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

/// The corner radii of one look: the M3 shape scale, stretched or tightened
/// around the radius of its medium step.
class ShapeScale {
  /// Builds the scale around [medium], the radius of cards in dp.
  const ShapeScale(this.medium, {required this.pillButtons});

  /// The scale for the corner preference of [settings].
  factory ShapeScale.of(AppearanceSettings settings) {
    switch (settings.cornerStyle) {
      case CornerStyle.clean:
        return const ShapeScale(_cleanMedium, pillButtons: false);
      case CornerStyle.consistent:
        return const ShapeScale(AppRadii.medium, pillButtons: true);
      case CornerStyle.custom:
        return ShapeScale(settings.customRadius, pillButtons: false);
    }
  }

  static const double _cleanMedium = 4;

  /// Radius of cards.
  final double medium;

  /// Whether buttons are full pills; otherwise they follow [medium].
  final bool pillButtons;

  /// Radius of chips.
  double get small => medium * 2 / 3;

  /// Radius of sheets and floating buttons.
  double get large => medium * 4 / 3;

  /// Radius of dialogs.
  double get extraLarge => medium * 7 / 3;

  /// Shape of cards and other medium surfaces.
  RoundedRectangleBorder get cardShape => _rounded(medium);

  /// Shape of buttons.
  OutlinedBorder get buttonShape =>
      pillButtons ? const StadiumBorder() : _rounded(medium);

  static RoundedRectangleBorder _rounded(double radius) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
}

/// M3 light and dark themes built from the brand seed or from the user's
/// appearance settings.
abstract final class AppTheme {
  /// The light theme with the default look.
  static ThemeData light() => build(Brightness.light);

  /// The dark theme with the default look.
  static ThemeData dark() => build(Brightness.dark);

  /// The theme for [brightness] with the user's [settings].
  ///
  /// [dynamicScheme] is the device palette for [brightness] (Material You)
  /// when the platform has one; it is used only if the user asked for it.
  static ThemeData build(
    Brightness brightness, {
    AppearanceSettings settings = const AppearanceSettings(),
    ColorScheme? dynamicScheme,
  }) {
    final colorScheme = _colorScheme(brightness, settings, dynamicScheme);
    final shapes = ShapeScale.of(settings);
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
        shape: shapes.cardShape,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shapes.small),
        ),
        selectedColor: colorScheme.primaryContainer,
        labelStyle: TextStyle(color: colorScheme.onSurface),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shapes.extraLarge),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(shapes.extraLarge),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shapes.large),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: shapes.buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: shapes.buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: shapes.buttonShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant),
    );
  }

  static ColorScheme _colorScheme(
    Brightness brightness,
    AppearanceSettings settings,
    ColorScheme? dynamicScheme,
  ) {
    if (settings.colorSource == ColorSource.dynamic && dynamicScheme != null) {
      return dynamicScheme;
    }
    final seed = settings.colorSource == ColorSource.custom
        ? Color(settings.customSeed)
        : SeedPreset.byId(settings.presetId).color;
    return ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  }
}
