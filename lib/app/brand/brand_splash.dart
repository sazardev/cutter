import 'package:cutter/app/brand/brand_mark.dart';
import 'package:cutter/app/theme/seed_presets.dart';
import 'package:flutter/material.dart';

/// Same width as the mark inside the native splash (52dp of its 108dp
/// canvas), so the hand-off from the system splash does not jump.
const double _splashMarkSize = 52;

/// The screen shown while the app reads its first settings: the brand mark on
/// the brand color, in light and dark alike, matching the native splash.
class BrandSplash extends StatelessWidget {
  /// Creates the splash.
  const BrandSplash({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: SeedPreset.violet.color);
    return Theme(
      data: ThemeData(colorScheme: scheme),
      child: Scaffold(
        backgroundColor: scheme.primary,
        body: const Center(child: BrandMark(size: _splashMarkSize)),
      ),
    );
  }
}
