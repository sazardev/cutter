import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/core/settings/settings_store.dart';
import 'package:cutter/features/settings/data/drift_appearance_repository.dart';
import 'package:cutter/features/settings/domain/appearance_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SettingsStore store;
  late DriftAppearanceRepository repository;

  setUp(() {
    db = AppDatabase.inMemory();
    store = SettingsStore(db);
    repository = DriftAppearanceRepository(store);
  });

  tearDown(() => db.close());

  test('loads the defaults from a fresh database', () async {
    expect(await repository.load(), const AppearanceSettings());
  });

  test('saves every field and loads the same settings back', () async {
    const settings = AppearanceSettings(
      themeMode: AppThemeMode.dark,
      colorSource: ColorSource.custom,
      presetId: 'teal',
      customSeed: 0xFF00897B,
      cornerStyle: CornerStyle.custom,
      customRadius: 20,
      textScale: 1.2,
    );

    await repository.save(settings);

    expect(await repository.load(), settings);
  });

  test('saving twice keeps one row per field', () async {
    await repository.save(const AppearanceSettings());
    await repository.save(
      const AppearanceSettings(themeMode: AppThemeMode.light),
    );

    expect(await db.select(db.appSettings).get(), hasLength(7));
    expect((await repository.load()).themeMode, AppThemeMode.light);
  });

  test('falls back to the default for unreadable or out-of-range values',
      () async {
    await store.writeAll({
      'appearance.theme_mode': 'sepia',
      'appearance.custom_seed': 'not a number',
      'appearance.text_scale': '9',
      'appearance.custom_radius': '-4',
    });

    final loaded = await repository.load();

    expect(loaded.themeMode, AppThemeMode.system);
    expect(loaded.customSeed, AppearanceSettings.defaultCustomSeed);
    expect(loaded.textScale, AppearanceSettings.maxTextScale);
    expect(loaded.customRadius, AppearanceSettings.minCustomRadius);
  });

  test('does not read the keys of other features', () async {
    await store.write('onboarding_completed', 'true');

    expect(await repository.load(), const AppearanceSettings());
  });
}
