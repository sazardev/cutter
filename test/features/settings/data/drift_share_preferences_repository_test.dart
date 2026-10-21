import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/core/settings/settings_store.dart';
import 'package:cutter/features/settings/data/drift_share_preferences_repository.dart';
import 'package:cutter/features/settings/domain/share_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftSharePreferencesRepository repository;

  setUp(() {
    database = AppDatabase.inMemory();
    repository = DriftSharePreferencesRepository(SettingsStore(database));
  });

  tearDown(() => database.close());

  test('nothing saved gives the defaults', () async {
    expect(await repository.load(), const SharePreferences());
  });

  test('every choice survives a save and a load', () async {
    const chosen = SharePreferences(
      showAfterExport: false,
      openSheetAutomatically: true,
      platforms: {SharePlatform.x, SharePlatform.snapchat},
      showWatch: false,
      showOpenFolder: false,
      showCopyPath: false,
    );

    await repository.save(chosen);

    expect(await repository.load(), chosen);
  });

  test('turning every platform off is kept, not replaced by the defaults',
      () async {
    await repository.save(const SharePreferences(platforms: {}));

    expect((await repository.load()).platforms, isEmpty);
  });
}
