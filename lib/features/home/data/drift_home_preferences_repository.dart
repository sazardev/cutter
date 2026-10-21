import 'package:cutter/core/settings/settings_store.dart';
import 'package:cutter/features/home/domain/home_preferences.dart';
import 'package:cutter/features/home/domain/home_preferences_repository.dart';

const _pinnedKey = 'home.pinned';
const _sortKey = 'home.sort';
const _archivedKey = 'home.archived';
const _trashKey = 'home.trash';

/// Stores the home list preferences as `app_settings` rows; the pinned ids
/// are one line of text separated by newlines.
class DriftHomePreferencesRepository implements HomePreferencesRepository {
  /// Creates a repository over [_store].
  DriftHomePreferencesRepository(this._store);

  final SettingsStore _store;

  @override
  Future<HomePreferences> load() async {
    final values = await _store.readPrefixed('home.');
    final pinned = (values[_pinnedKey] ?? '')
        .split('\n')
        .where((id) => id.isNotEmpty)
        .toSet();
    final archived = (values[_archivedKey] ?? '')
        .split('\n')
        .where((id) => id.isNotEmpty)
        .toSet();
    // One `id|milliseconds` entry per line.
    final trashed = <String, int>{};
    for (final line in (values[_trashKey] ?? '').split('\n')) {
      final parts = line.split('|');
      final at = parts.length == 2 ? int.tryParse(parts[1]) : null;
      if (at != null && parts[0].isNotEmpty) trashed[parts[0]] = at;
    }
    final sort = ProjectSort.values.where((s) => s.name == values[_sortKey]);
    return HomePreferences(
      pinnedIds: pinned,
      archivedIds: archived,
      trashedAtMs: trashed,
      sort: sort.isEmpty ? ProjectSort.recent : sort.first,
    );
  }

  @override
  Future<void> save(HomePreferences preferences) {
    return _store.writeAll({
      _pinnedKey: preferences.pinnedIds.join('\n'),
      _archivedKey: preferences.archivedIds.join('\n'),
      _trashKey: [
        for (final e in preferences.trashedAtMs.entries) '${e.key}|${e.value}',
      ].join('\n'),
      _sortKey: preferences.sort.name,
    });
  }
}
