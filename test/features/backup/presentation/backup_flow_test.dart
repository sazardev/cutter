import 'dart:io';

import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/core/engine/media_engine.dart';
import 'package:cutter/features/backup/presentation/backup_flow.dart';
import 'package:cutter/features/editor/data/media_library.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/tools/export_panel.dart';
import 'package:cutter/features/home/presentation/home_page.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/engine/fake_media_engine.dart';

/// Lets real file work and the frames that follow it alternate: each file
/// operation finishes in the real event loop, and the code waiting on it runs
/// when the test pumps. A spinner may still be animating, so no pumpAndSettle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  late Directory sandbox;
  late AppDatabase db;
  late String restoreFrom;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('cutter_backup_flow');
    db = AppDatabase.inMemory();
    restoreFrom = '';
  });

  tearDown(() async {
    await db.close();
    sandbox.deleteSync(recursive: true);
  });

  Future<void> seed(WidgetTester tester) async {
    final video = File('${sandbox.path}/trip.mp4')..writeAsStringSync('video');
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
              sourceUri: Value(video.path),
              startMs: const Value(0),
              durationMs: const Value(4000),
              inPointMs: const Value(0),
              outPointMs: const Value(4000),
              reversed: const Value(false),
              volume: const Value(1),
              filterId: const Value(null),
              adjustmentsJson: const Value('{}'),
            ),
          );
    });
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          mediaEngineProvider.overrideWithValue(FakeMediaEngine()),
          exportDirectoryProvider.overrideWith(
            (ref) async => Directory('${sandbox.path}/exports'),
          ),
          mediaLibraryProvider.overrideWith(
            (ref) async => MediaLibrary(
              root: Directory('${sandbox.path}/library'),
              volatileRoots: const [],
            ),
          ),
          backupPickerProvider.overrideWithValue(() async => restoreFrom),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomePage(),
        ),
      ),
    );
    await _settle(tester);
  }

  testWidgets('backs a project up and restores it as a new project',
      (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await seed(tester);
    await pump(tester);

    await tester.tap(find.byTooltip(l10n.homeProjectMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.homeBackupAction));
    await _settle(tester);

    expect(find.text(l10n.backupSavedTitle), findsOneWidget);
    expect(find.text(l10n.backupSavedBody(1)), findsOneWidget);
    final backups = Directory('${sandbox.path}/exports').listSync();
    expect(backups, hasLength(1));
    expect(backups.single.path, endsWith('.cutter'));
    restoreFrom = backups.single.path;

    await tester.tap(find.text(l10n.importReportClose));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(l10n.homeRestoreBackupAction));
    await _settle(tester);

    final restoredName = l10n.backupRestoredName('Holiday');
    expect(find.text(l10n.restoreDoneTitle), findsOneWidget);
    expect(find.text(l10n.restoreDoneBody(restoredName)), findsOneWidget);
    await tester.tap(find.text(l10n.importReportClose));
    await _settle(tester);

    expect(find.text('Holiday'), findsOneWidget);
    expect(find.text(restoredName), findsOneWidget);
    final projects = await tester.runAsync(
      () => db.select(db.editorProjects).get(),
    );
    expect(projects, hasLength(2));
    final clips = await tester.runAsync(() => db.select(db.editorClips).get());
    expect(clips!.map((c) => c.sourceUri).toSet(), hasLength(2));
  });

  testWidgets('a file that is not a backup is explained', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await seed(tester);
    restoreFrom = File('${sandbox.path}/trip.mp4').path;
    await pump(tester);

    await tester.tap(find.byTooltip(l10n.homeRestoreBackupAction));
    await _settle(tester);

    expect(find.text(l10n.restoreFailedTitle), findsOneWidget);
    expect(find.text(l10n.backupNotABackup), findsOneWidget);
    final projects = await tester.runAsync(
      () => db.select(db.editorProjects).get(),
    );
    expect(projects, hasLength(1));
  });
}
