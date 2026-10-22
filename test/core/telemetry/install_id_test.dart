import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/core/settings/settings_store.dart';
import 'package:cutter/core/telemetry/install_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SettingsStore store;

  setUp(() {
    db = AppDatabase.inMemory();
    store = SettingsStore(db);
  });

  tearDown(() => db.close());

  test('creates a UUID and keeps it across launches', () async {
    final first = await loadInstallId(store);
    final second = await loadInstallId(store);

    expect(first, isNotEmpty);
    expect(
      first,
      matches(
        RegExp(
          '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
          r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(second, first);
    expect(await store.read(installIdKey), first);
  });

  test('replaces an empty stored identifier', () async {
    await store.write(installIdKey, '  ');

    final id = await loadInstallId(store);

    expect(id.trim(), isNotEmpty);
    expect(await store.read(installIdKey), id);
  });
}
