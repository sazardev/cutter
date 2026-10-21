import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/core/settings/settings_store.dart';
import 'package:cutter/features/home/data/drift_home_preferences_repository.dart';
import 'package:cutter/features/home/domain/home_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DriftHomePreferencesRepository repository;

  setUp(() {
    db = AppDatabase.inMemory();
    repository = DriftHomePreferencesRepository(SettingsStore(db));
  });

  tearDown(() => db.close());

  test('defaults to nothing pinned and recent first', () async {
    expect(await repository.load(), const HomePreferences());
  });

  test('keeps the pinned ids and the sort', () async {
    const prefs = HomePreferences(
      pinnedIds: {'p1', 'p2'},
      sort: ProjectSort.name,
    );
    await repository.save(prefs);
    expect(await repository.load(), prefs);

    await repository.save(prefs.togglePin('p1'));
    expect((await repository.load()).pinnedIds, {'p2'});
  });

  test('keeps archived and trashed projects', () async {
    const prefs = HomePreferences(
      archivedIds: {'a'},
      trashedAtMs: {'b': 123, 'c': 456},
    );
    await repository.save(prefs);
    expect(await repository.load(), prefs);
  });
}
