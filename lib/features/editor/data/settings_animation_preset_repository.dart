import 'dart:convert';

import 'package:cutter/core/settings/settings_store.dart';
import 'package:cutter/features/editor/domain/animation_preset.dart';

const _key = 'animation_presets';

/// Keeps the user's animation presets as one JSON list in `app_settings`, so
/// they need no table of their own. An unreadable value counts as none.
class SettingsAnimationPresetRepository implements AnimationPresetRepository {
  /// Creates the repository over [_store].
  SettingsAnimationPresetRepository(this._store);

  final SettingsStore _store;

  @override
  Future<List<AnimationPreset>> all() async {
    final raw = await _store.read(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [
        for (final entry in jsonDecode(raw) as List<dynamic>)
          AnimationPreset.fromJson((entry as Map).cast<String, Object?>()),
      ];
    } on Object {
      return const [];
    }
  }

  @override
  Future<void> save(AnimationPreset preset) async {
    final presets = await all();
    final next = [
      for (final p in presets)
        if (p.id != preset.id) p,
      preset,
    ];
    await _write(next);
  }

  @override
  Future<void> delete(String id) async {
    final presets = await all();
    await _write([
      for (final p in presets)
        if (p.id != id) p,
    ]);
  }

  Future<void> _write(List<AnimationPreset> presets) => _store.write(
        _key,
        jsonEncode([for (final p in presets) p.toJson()]),
      );
}
