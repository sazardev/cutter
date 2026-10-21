import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/core/settings/settings_store.dart';
import 'package:cutter/features/settings/data/drift_export_preferences_repository.dart';
import 'package:cutter/features/settings/domain/export_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DriftExportPreferencesRepository repository;

  setUp(() {
    db = AppDatabase.inMemory();
    repository = DriftExportPreferencesRepository(SettingsStore(db));
  });

  tearDown(() => db.close());

  test('defaults to the default folder and the gallery', () async {
    expect(await repository.load(), const ExportPreferences());
  });

  test('keeps a folder and the gallery choice, and can clear the folder',
      () async {
    const custom = ExportPreferences(
      directory: '/storage/emulated/0/Movies/Mine',
      saveToGallery: false,
    );
    await repository.save(custom);
    expect(await repository.load(), custom);

    await repository.save(custom.copyWith(clearDirectory: true));
    expect((await repository.load()).directory, isNull);
  });
}
