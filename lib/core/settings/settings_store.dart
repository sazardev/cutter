import 'package:cutter/core/db/app_database.dart';

/// Device-level preferences as text values under keys, kept in the
/// `app_settings` table with the onboarding flag.
class SettingsStore {
  /// Creates the store on [_db].
  SettingsStore(this._db);

  final AppDatabase _db;

  /// The value stored under [key], or null.
  Future<String?> read(String key) async {
    final row = await (_db.select(_db.appSettings)
          ..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  /// Every value stored under a key that starts with [prefix], by key.
  Future<Map<String, String>> readPrefixed(String prefix) async {
    final rows = await _db.select(_db.appSettings).get();
    return {
      for (final row in rows)
        if (row.key.startsWith(prefix)) row.key: row.value,
    };
  }

  /// Stores [value] under [key].
  Future<void> write(String key, String value) {
    return _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }

  /// Stores every entry of [values] in one transaction.
  Future<void> writeAll(Map<String, String> values) {
    return _db.transaction(() async {
      for (final entry in values.entries) {
        await write(entry.key, entry.value);
      }
    });
  }
}
