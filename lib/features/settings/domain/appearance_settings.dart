import 'package:flutter/foundation.dart' show immutable;

/// Which brightness the app uses.
enum AppThemeMode {
  /// Follow the operating system.
  system,

  /// Always light.
  light,

  /// Always dark.
  dark,
}

/// Where the color scheme comes from.
enum ColorSource {
  /// The wallpaper palette of the device (Material You), when it has one.
  dynamic,

  /// One of the built-in seed colors, picked by [AppearanceSettings.presetId].
  preset,

  /// A seed color the user picked, [AppearanceSettings.customSeed].
  custom,
}

/// How rounded surfaces and buttons are.
enum CornerStyle {
  /// Tight corners: a flat, uncluttered look.
  clean,

  /// The Material 3 shape scale as designed.
  consistent,

  /// The user chooses the radius, [AppearanceSettings.customRadius].
  custom,
}

/// How the user wants the app to look. Plain, immutable and independent of
/// Flutter so the domain stays testable on its own.
@immutable
class AppearanceSettings {
  /// Creates the settings; every field has the app default.
  const AppearanceSettings({
    this.themeMode = AppThemeMode.system,
    this.colorSource = ColorSource.preset,
    this.presetId = defaultPresetId,
    this.customSeed = defaultCustomSeed,
    this.cornerStyle = CornerStyle.consistent,
    this.customRadius = defaultCustomRadius,
    this.textScale = defaultTextScale,
  });

  /// The id of the brand seed color.
  static const String defaultPresetId = 'violet';

  /// The seed shown when the user opens the custom color picker (ARGB).
  static const int defaultCustomSeed = 0xFF6750A4;

  /// The radius of the medium shape step, in dp, that matches the M3 scale.
  static const double defaultCustomRadius = 12;

  /// Smallest radius of the medium shape step the user can pick.
  static const double minCustomRadius = 0;

  /// Largest radius of the medium shape step the user can pick.
  static const double maxCustomRadius = 24;

  /// No extra scaling on top of the system font size.
  static const double defaultTextScale = 1;

  /// Smallest text scale the user can pick.
  static const double minTextScale = 0.8;

  /// Largest text scale the user can pick.
  static const double maxTextScale = 1.4;

  /// Light, dark or follow the system.
  final AppThemeMode themeMode;

  /// Where the colors come from.
  final ColorSource colorSource;

  /// The built-in seed in use when [colorSource] is [ColorSource.preset].
  final String presetId;

  /// The picked seed (ARGB) in use when [colorSource] is [ColorSource.custom].
  final int customSeed;

  /// How rounded the corners are.
  final CornerStyle cornerStyle;

  /// Radius of the medium shape step in dp when [cornerStyle] is
  /// [CornerStyle.custom].
  final double customRadius;

  /// Factor applied on top of the system font size.
  final double textScale;

  /// True when every field has its default.
  bool get isDefault => this == const AppearanceSettings();

  /// A copy with the given fields replaced.
  AppearanceSettings copyWith({
    AppThemeMode? themeMode,
    ColorSource? colorSource,
    String? presetId,
    int? customSeed,
    CornerStyle? cornerStyle,
    double? customRadius,
    double? textScale,
  }) {
    return AppearanceSettings(
      themeMode: themeMode ?? this.themeMode,
      colorSource: colorSource ?? this.colorSource,
      presetId: presetId ?? this.presetId,
      customSeed: customSeed ?? this.customSeed,
      cornerStyle: cornerStyle ?? this.cornerStyle,
      customRadius: customRadius ?? this.customRadius,
      textScale: textScale ?? this.textScale,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppearanceSettings &&
        other.themeMode == themeMode &&
        other.colorSource == colorSource &&
        other.presetId == presetId &&
        other.customSeed == customSeed &&
        other.cornerStyle == cornerStyle &&
        other.customRadius == customRadius &&
        other.textScale == textScale;
  }

  @override
  int get hashCode => Object.hash(
        themeMode,
        colorSource,
        presetId,
        customSeed,
        cornerStyle,
        customRadius,
        textScale,
      );
}
