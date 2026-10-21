import 'package:cutter/core/settings/settings_store.dart';
import 'package:cutter/features/settings/domain/appearance_repository.dart';
import 'package:cutter/features/settings/domain/appearance_settings.dart';

const _prefix = 'appearance.';
const _themeModeKey = '${_prefix}theme_mode';
const _colorSourceKey = '${_prefix}color_source';
const _presetIdKey = '${_prefix}preset_id';
const _customSeedKey = '${_prefix}custom_seed';
const _cornerStyleKey = '${_prefix}corner_style';
const _customRadiusKey = '${_prefix}custom_radius';
const _textScaleKey = '${_prefix}text_scale';

/// Stores the appearance preferences as one `app_settings` row per field.
class DriftAppearanceRepository implements AppearanceRepository {
  /// Creates a repository over [_store].
  DriftAppearanceRepository(this._store);

  final SettingsStore _store;

  @override
  Future<AppearanceSettings> load() async {
    final values = await _store.readPrefixed(_prefix);
    const defaults = AppearanceSettings();
    return AppearanceSettings(
      themeMode: _enumOf(
        AppThemeMode.values,
        values[_themeModeKey],
        defaults.themeMode,
      ),
      colorSource: _enumOf(
        ColorSource.values,
        values[_colorSourceKey],
        defaults.colorSource,
      ),
      presetId: values[_presetIdKey] ?? defaults.presetId,
      customSeed:
          int.tryParse(values[_customSeedKey] ?? '') ?? defaults.customSeed,
      cornerStyle: _enumOf(
        CornerStyle.values,
        values[_cornerStyleKey],
        defaults.cornerStyle,
      ),
      customRadius: _clamped(
        values[_customRadiusKey],
        AppearanceSettings.minCustomRadius,
        AppearanceSettings.maxCustomRadius,
        defaults.customRadius,
      ),
      textScale: _clamped(
        values[_textScaleKey],
        AppearanceSettings.minTextScale,
        AppearanceSettings.maxTextScale,
        defaults.textScale,
      ),
    );
  }

  @override
  Future<void> save(AppearanceSettings settings) {
    return _store.writeAll({
      _themeModeKey: settings.themeMode.name,
      _colorSourceKey: settings.colorSource.name,
      _presetIdKey: settings.presetId,
      _customSeedKey: settings.customSeed.toString(),
      _cornerStyleKey: settings.cornerStyle.name,
      _customRadiusKey: settings.customRadius.toString(),
      _textScaleKey: settings.textScale.toString(),
    });
  }
}

T _enumOf<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

double _clamped(String? raw, double min, double max, double fallback) {
  final value = double.tryParse(raw ?? '');
  if (value == null || value.isNaN) return fallback;
  return value.clamp(min, max);
}
