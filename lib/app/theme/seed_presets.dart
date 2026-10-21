import 'package:flutter/painting.dart';

/// A built-in seed color the user can pick for the color scheme.
class SeedPreset {
  const SeedPreset._(this.id, this.color);

  /// Stable id stored in the settings.
  final String id;

  /// The seed the M3 scheme is generated from.
  final Color color;

  /// The brand seed, used when a stored id is unknown.
  static const SeedPreset violet = SeedPreset._('violet', Color(0xFF6750A4));

  /// Every preset, in the order the picker shows them.
  static const List<SeedPreset> all = [
    violet,
    SeedPreset._('blue', Color(0xFF1E6BD6)),
    SeedPreset._('teal', Color(0xFF00897B)),
    SeedPreset._('green', Color(0xFF3F8F3F)),
    SeedPreset._('orange', Color(0xFFD9731A)),
    SeedPreset._('red', Color(0xFFC62F3E)),
    SeedPreset._('pink', Color(0xFFC2457F)),
  ];

  /// The preset with [id], or the brand seed when there is none.
  static SeedPreset byId(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return violet;
  }
}
