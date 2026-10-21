import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/core/settings/settings_store.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/settings/data/drift_appearance_repository.dart';
import 'package:cutter/features/settings/domain/appearance_repository.dart';
import 'package:cutter/features/settings/domain/appearance_settings.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Brightness, ColorScheme, ThemeData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The domain port for the appearance preferences, backed by drift.
final appearanceRepositoryProvider = Provider<AppearanceRepository>(
  (ref) => DriftAppearanceRepository(
    SettingsStore(ref.watch(appDatabaseProvider)),
  ),
);

/// The preferences read before the first frame, so the app never flashes the
/// default look. `main` overrides it with the saved settings.
final initialAppearanceProvider = Provider<AppearanceSettings>(
  (ref) => const AppearanceSettings(),
);

/// The appearance the whole app is drawn with. Changing it repaints the app
/// at once and saves it in the background.
final appearanceProvider =
    NotifierProvider<AppearanceController, AppearanceSettings>(
  AppearanceController.new,
);

/// Holds the appearance preferences and persists each change.
class AppearanceController extends Notifier<AppearanceSettings> {
  @override
  AppearanceSettings build() => ref.watch(initialAppearanceProvider);

  /// Repaints the app with [change] applied without saving it, for controls
  /// that fire continuously while dragging; call [commit] when they end.
  void preview(AppearanceSettings Function(AppearanceSettings current) change) {
    state = change(state);
  }

  /// Saves the current preferences.
  Future<void> commit() async {
    try {
      await ref.read(appearanceRepositoryProvider).save(state);
    } on Object catch (error) {
      // The look stays as chosen for this session; only persistence is lost.
      debugPrint('Could not save the appearance settings: $error');
    }
  }

  /// Replaces the preferences with [change] applied to the current ones and
  /// saves them.
  Future<void> update(
    AppearanceSettings Function(AppearanceSettings current) change,
  ) {
    preview(change);
    return commit();
  }

  /// Goes back to the default look.
  Future<void> reset() => update((_) => const AppearanceSettings());
}

/// Whether the device offers a wallpaper palette (Material You).
final dynamicColorAvailableProvider = FutureProvider<bool>((ref) async {
  try {
    return await DynamicColorPlugin.getCorePalette() != null;
  } on Object {
    return false;
  }
});

/// The dark wallpaper palette of the device, or null when it has none.
final deviceDarkSchemeProvider = FutureProvider<ColorScheme?>((ref) async {
  try {
    final palette = await DynamicColorPlugin.getCorePalette();
    return palette?.toColorScheme(brightness: Brightness.dark);
  } on Object {
    return null;
  }
});

/// The theme of the editor screens: always dark (DESIGN.md), but with the
/// color, corners and palette the user chose.
final editorThemeProvider = Provider<ThemeData>(
  (ref) => AppTheme.build(
    Brightness.dark,
    settings: ref.watch(appearanceProvider),
    dynamicScheme: ref.watch(deviceDarkSchemeProvider).valueOrNull,
  ),
);
