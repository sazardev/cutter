import 'dart:io';

import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/features/editor/data/media_library.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/settings/presentation/settings_page.dart';
import 'package:cutter/features/storage/presentation/storage_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  late Directory sandbox;
  late Directory media;
  late Directory cache;
  late AppDatabase db;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('cutter_storage_ui');
    media = Directory('${sandbox.path}/media')..createSync();
    cache = Directory('${sandbox.path}/cache')..createSync();
    db = AppDatabase.inMemory();
  });

  tearDown(() async {
    await db.close();
    sandbox.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          cacheDirectoryProvider.overrideWith((ref) async => cache),
          mediaLibraryProvider.overrideWith(
            (ref) async => MediaLibrary(root: media, volatileRoots: const []),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Storage'));
    await _settle(tester);
  }

  Future<void> seedProject(WidgetTester tester, File used) async {
    await tester.runAsync(() async {
      await db.into(db.editorProjects).insert(
            const EditorProjectsCompanion(
              id: Value('p1'),
              name: Value('Holiday'),
              createdAtMs: Value(1),
              updatedAtMs: Value(1),
              canvasWidth: Value(1080),
              canvasHeight: Value(1920),
              fps: Value(30),
            ),
          );
      await db.into(db.editorLayers).insert(
            const EditorLayersCompanion(
              id: Value('l1'),
              projectId: Value('p1'),
              position: Value(0),
              kind: Value('video'),
              volume: Value(1),
              muted: Value(false),
            ),
          );
      await db.into(db.editorClips).insert(
            EditorClipsCompanion(
              id: const Value('c1'),
              layerId: const Value('l1'),
              sortKey: const Value(0),
              sourceUri: Value(used.path),
              startMs: const Value(0),
              durationMs: const Value(1000),
              inPointMs: const Value(0),
              outPointMs: const Value(1000),
              reversed: const Value(false),
              volume: const Value(1),
              filterId: const Value(null),
              adjustmentsJson: const Value('{}'),
            ),
          );
    });
  }

  testWidgets('shows the total, the cache and each project', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final used = File('${media.path}/trip.mp4')
      ..writeAsBytesSync(List.filled(2048, 1));
    File('${cache.path}/tmp.bin').writeAsBytesSync(List.filled(1024, 1));
    await seedProject(tester, used);

    await pump(tester);

    expect(find.text(l10n.storageTotal('3.0 KB')), findsOneWidget);
    expect(find.text('Holiday'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
  });

  testWidgets('clearing the cache removes old files and says how much',
      (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final old = File('${cache.path}/old.bin')
      ..writeAsBytesSync(List.filled(1024, 1))
      ..setLastModifiedSync(DateTime.now().subtract(const Duration(days: 3)));
    final fresh = File('${cache.path}/fresh.bin')
      ..writeAsBytesSync(List.filled(512, 1));
    await pump(tester);

    await tester.tap(find.text(l10n.storageClearCache));
    await _settle(tester);

    expect(old.existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue);
    expect(find.text(l10n.storageFreed('1.0 KB')), findsOneWidget);
  });

  testWidgets('unused media is deleted only after confirming', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final used = File('${media.path}/trip.mp4')
      ..writeAsBytesSync(List.filled(2048, 1));
    final orphan = File('${media.path}/orphan.mp4')
      ..writeAsBytesSync(List.filled(4096, 1));
    await seedProject(tester, used);
    await pump(tester);

    await tester.tap(find.text(l10n.storageCleanUnused).first);
    await tester.pumpAndSettle();
    expect(find.text(l10n.storageCleanTitle), findsOneWidget);

    await tester.tap(find.text(l10n.cancelAction));
    await tester.pumpAndSettle();
    expect(orphan.existsSync(), isTrue);

    await tester.tap(find.text(l10n.storageCleanUnused).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(l10n.storageCleanUnused),
      ),
    );
    await _settle(tester);

    expect(orphan.existsSync(), isFalse);
    expect(used.existsSync(), isTrue);
  });
}
