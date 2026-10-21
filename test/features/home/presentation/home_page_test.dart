import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/core/engine/media_engine.dart';
import 'package:cutter/core/settings/settings_store.dart';
import 'package:cutter/features/editor/data/drift_export_library.dart';
import 'package:cutter/features/editor/domain/export_record.dart';
import 'package:cutter/features/editor/presentation/editor_page.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/home/data/drift_home_preferences_repository.dart';
import 'package:cutter/features/home/presentation/home_page.dart';
import 'package:cutter/features/home/presentation/home_providers.dart';
import 'package:cutter/features/onboarding/presentation/onboarding_page.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/engine/fake_media_engine.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pumpHome(
  WidgetTester tester,
  AppDatabase db,
  Locale locale, {
  ExportLibrary? library,
}) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        mediaEngineProvider.overrideWithValue(FakeMediaEngine()),
        if (library != null) exportLibraryProvider.overrideWithValue(library),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HomePage(),
      ),
    ),
  );
  await _settle(tester);
}

void main() {
  for (final locale in const [Locale('en'), Locale('es')]) {
    final tag = locale.languageCode;

    testWidgets('shows the empty state and the templates ($tag)',
        (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      final l10n = await AppLocalizations.delegate.load(locale);

      await _pumpHome(tester, db, locale);

      expect(find.text(l10n.homeEmptyTitle), findsOneWidget);
      expect(find.text(l10n.newProjectAction), findsOneWidget);
      expect(find.text(l10n.templatesTitle), findsOneWidget);
      expect(find.text(l10n.templateVerticalStoryTitle), findsOneWidget);
      expect(find.text(l10n.templateVoiceOverTitle), findsOneWidget);
      expect(find.text(l10n.templatePhotoMontageTitle), findsOneWidget);
    });

    testWidgets('creates a project and opens it in the editor ($tag)',
        (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      final l10n = await AppLocalizations.delegate.load(locale);
      await _pumpHome(tester, db, locale);

      await tester.tap(find.text(l10n.newProjectAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.newProjectSkip));
      await _settle(tester);

      expect(find.byType(EditorPage), findsOneWidget);
      expect(find.text(l10n.defaultProjectName(1)), findsOneWidget);
      expect(find.text(l10n.emptyTimelineTitle), findsOneWidget);
      final projects = await tester.runAsync(
        () => db.select(db.editorProjects).get(),
      );
      expect(projects, hasLength(1));
    });

    testWidgets('a template creates the project with its layers ($tag)',
        (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      final l10n = await AppLocalizations.delegate.load(locale);
      await _pumpHome(tester, db, locale);

      await tester.tap(find.text(l10n.templateVerticalStoryTitle));
      await tester.pumpAndSettle();
      // A template picked on the home screen skips the start step.
      expect(find.text(l10n.newProjectFormatTitle), findsOneWidget);
      await tester.tap(find.text(l10n.newProjectSkip));
      await _settle(tester);

      final layers = await tester.runAsync(
        () => db.select(db.editorLayers).get(),
      );
      expect(layers!.map((layer) => layer.kind).toSet(), {'video', 'audio'});
      expect(find.byType(EditorPage), findsOneWidget);
      // The template's layers wait for media.
      expect(find.text(l10n.emptyTimelineTitle), findsOneWidget);
    });
  }

  testWidgets('lists stored projects and the help button opens the intro',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.runAsync(
      () => ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          mediaEngineProvider.overrideWithValue(FakeMediaEngine()),
        ],
      ).read(createProjectProvider).call(name: 'Holiday'),
    );

    await _pumpHome(tester, db, const Locale('en'));

    expect(find.text('Holiday'), findsOneWidget);
    expect(find.text(l10n.homeEmptyTitle), findsNothing);
    // Templates are only a shortcut while there is nothing else to open.
    expect(find.text(l10n.templatesTitle), findsNothing);

    await tester.tap(find.byTooltip(l10n.helpAction));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingPage), findsOneWidget);
  });

  testWidgets('the guide collects format, frame rate and name', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _pumpHome(tester, db, const Locale('en'));

    await tester.tap(find.text(l10n.newProjectAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.onboardingNext));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(l10n.canvasLandscape));
    await tester.tap(find.text(l10n.onboardingNext));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.fpsSmoothTitle));
    await tester.tap(find.text(l10n.onboardingNext));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Road trip');
    await tester.tap(find.text(l10n.newProjectCreate));
    await _settle(tester);

    expect(find.byType(EditorPage), findsOneWidget);
    final projects = await tester.runAsync(
      () => db.select(db.editorProjects).get(),
    );
    expect(projects!.single.name, 'Road trip');
    expect(projects.single.canvasWidth, 1920);
    expect(projects.single.canvasHeight, 1080);
    expect(projects.single.fps, 60);
  });

  testWidgets('searches, pins and pages the project list', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.runAsync(() async {
      final create = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          mediaEngineProvider.overrideWithValue(FakeMediaEngine()),
        ],
      ).read(createProjectProvider);
      for (var i = 1; i <= 14; i++) {
        await create(name: i == 3 ? 'Beach' : 'Clip $i');
      }
    });
    await _pumpHome(tester, db, const Locale('en'));
    // Tall enough that the lazy list builds every row.
    tester.view.physicalSize = const Size(900, 4000);
    await tester.pumpAndSettle();

    expect(find.text(l10n.homeShowMore), findsOneWidget);
    expect(find.text(l10n.homeShowing(12, 14)), findsOneWidget);
    await tester.tap(find.text(l10n.homeShowMore));
    await tester.pumpAndSettle();
    expect(find.text(l10n.homeShowMore), findsNothing);

    await tester.enterText(find.byType(SearchBar), 'beach');
    await tester.pumpAndSettle();
    expect(find.text('Beach'), findsOneWidget);
    expect(find.text('Clip 4'), findsNothing);

    await tester.tap(find.byTooltip(l10n.homePinAction));
    await tester.pumpAndSettle();
    expect(find.byTooltip(l10n.homeUnpinAction), findsOneWidget);

    await tester.enterText(find.byType(SearchBar), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text(l10n.homeNoResultsTitle), findsOneWidget);
    await tester.tap(find.text(l10n.homeClearFilters));
    await tester.pumpAndSettle();
    expect(find.text('Beach'), findsOneWidget);
    expect(find.text('Clip 4'), findsOneWidget);
  });

  Future<void> menu(
    WidgetTester tester,
    AppLocalizations l10n,
    String item,
  ) async {
    await tester.tap(find.byTooltip(l10n.homeProjectMenu).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  Future<AppDatabase> projectDb(WidgetTester tester, List<String> names) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() async {
      final create = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          mediaEngineProvider.overrideWithValue(FakeMediaEngine()),
        ],
      ).read(createProjectProvider);
      for (final name in names) {
        await create(name: name);
      }
    });
    return db;
  }

  testWidgets('renames a project from its menu', (tester) async {
    final db = await projectDb(tester, ['Holiday']);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _pumpHome(tester, db, const Locale('en'));

    await menu(tester, l10n, l10n.renameAction);
    await tester.enterText(find.byType(TextField).last, 'Summer');
    await tester.tap(find.widgetWithText(FilledButton, l10n.renameAction));
    await _settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('Summer'), findsOneWidget);
    expect(find.text('Holiday'), findsNothing);
  });

  testWidgets('archiving hides a project and it stays in Archived',
      (tester) async {
    final db = await projectDb(tester, ['Holiday']);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _pumpHome(tester, db, const Locale('en'));

    await menu(tester, l10n, l10n.homeArchiveAction);
    expect(find.text('Holiday'), findsNothing);

    await tester.tap(find.byTooltip(l10n.homeFilterTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.homeScopeCount(l10n.homeScopeArchived, 1)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.homeFilterShowResults(1)));
    await tester.pumpAndSettle();
    expect(find.text('Holiday'), findsOneWidget);

    await menu(tester, l10n, l10n.homeUnarchiveAction);
    expect(find.text('Holiday'), findsNothing);
    final rows =
        await tester.runAsync(() => db.select(db.editorProjects).get());
    expect(rows, hasLength(1));
  });

  testWidgets('trash keeps a project, restores it or deletes it for good',
      (tester) async {
    final db = await projectDb(tester, ['Holiday']);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _pumpHome(tester, db, const Locale('en'));

    await menu(tester, l10n, l10n.homeTrashAction);
    expect(find.text(l10n.homeTrashTitle('Holiday')), findsOneWidget);
    // Cancelling keeps it.
    await tester.tap(find.text(l10n.cancelAction));
    await tester.pumpAndSettle();
    expect(find.text('Holiday'), findsOneWidget);

    await menu(tester, l10n, l10n.homeTrashAction);
    await tester.tap(find.widgetWithText(FilledButton, l10n.homeTrashAction));
    await tester.pumpAndSettle();
    expect(find.text('Holiday'), findsNothing);
    // Still stored: the trash is not a delete.
    var rows = await tester.runAsync(() => db.select(db.editorProjects).get());
    expect(rows, hasLength(1));

    await tester.tap(find.byTooltip(l10n.homeFilterTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.homeScopeCount(l10n.homeScopeTrash, 1)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.homeFilterShowResults(1)));
    await tester.pumpAndSettle();
    expect(find.text(l10n.homeTrashDaysLeft(7)), findsOneWidget);

    // Restore brings it back.
    await menu(tester, l10n, l10n.homeRestoreAction);
    expect(find.text('Holiday'), findsNothing);
    await tester.tap(find.byTooltip(l10n.homeFilterTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.homeProjectsSection));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.homeFilterShowResults(1)));
    await tester.pumpAndSettle();
    expect(find.text('Holiday'), findsOneWidget);

    // Trash it again and delete it for good.
    await menu(tester, l10n, l10n.homeTrashAction);
    await tester.tap(find.widgetWithText(FilledButton, l10n.homeTrashAction));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.homeFilterTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.homeScopeCount(l10n.homeScopeTrash, 1)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.homeFilterShowResults(1)));
    await tester.pumpAndSettle();
    await menu(tester, l10n, l10n.homeDeleteNowAction);
    expect(find.text(l10n.homeDeleteTitle('Holiday')), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, l10n.homeDeleteAction));
    await _settle(tester);

    rows = await tester.runAsync(() => db.select(db.editorProjects).get());
    expect(rows, isEmpty);
  });

  testWidgets('a project trashed more than a week ago is deleted on its own',
      (tester) async {
    final db = await projectDb(tester, ['Old one', 'Fresh']);
    final ids =
        (await tester.runAsync(() => db.select(db.editorProjects).get()))!;
    final old = ids.firstWhere((p) => p.name == 'Old one').id;
    final eightDaysAgo =
        DateTime.now().subtract(const Duration(days: 8)).millisecondsSinceEpoch;
    await tester.runAsync(
      () => SettingsStore(db).write('home.trash', '$old|$eightDaysAgo'),
    );
    final prefs = await tester.runAsync(
      () => DriftHomePreferencesRepository(SettingsStore(db)).load(),
    );

    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          mediaEngineProvider.overrideWithValue(FakeMediaEngine()),
          initialHomePreferencesProvider.overrideWithValue(prefs!),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomePage(),
        ),
      ),
    );
    await _settle(tester);
    await _settle(tester);

    final rows =
        await tester.runAsync(() => db.select(db.editorProjects).get());
    expect(rows!.map((p) => p.name), ['Fresh']);
  });

  testWidgets(
      'the filter screen sorts and narrows the list, pins get a section',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.runAsync(() async {
      final create = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          mediaEngineProvider.overrideWithValue(FakeMediaEngine()),
        ],
      ).read(createProjectProvider);
      await create(name: 'Zebra');
      await create(name: 'Apple');
    });
    await _pumpHome(tester, db, const Locale('en'));

    // Pin one: it moves to its own section.
    await tester.tap(find.byTooltip(l10n.homePinAction).last);
    await tester.pumpAndSettle();
    expect(find.text(l10n.homePinnedSection), findsOneWidget);
    expect(find.text(l10n.homeProjectsSection), findsOneWidget);

    // Open the modal, sort by name and keep only empty projects.
    await tester.tap(find.byTooltip(l10n.homeFilterTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.homeSortName));
    await tester.tap(find.text(l10n.homeFilterEmpty));
    await tester.pumpAndSettle();
    expect(find.text(l10n.homeFilterShowResults(2)), findsOneWidget);

    // Narrow to a length no project has: the button says so.
    await tester.tap(find.text(l10n.homeLengthLong));
    await tester.pumpAndSettle();
    expect(find.text(l10n.homeFilterShowResults(0)), findsOneWidget);

    await tester.tap(find.text(l10n.homeFilterReset));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.homeFilterShowResults(2)));
    await tester.pumpAndSettle();
    expect(find.text('Zebra'), findsOneWidget);
    expect(find.text('Apple'), findsOneWidget);
  });

  testWidgets('typing in the search offers matching project names',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() async {
      final create = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          mediaEngineProvider.overrideWithValue(FakeMediaEngine()),
        ],
      ).read(createProjectProvider);
      await create(name: 'Beach trip');
      await create(name: 'Mountain');
    });
    await _pumpHome(tester, db, const Locale('en'));

    await tester.enterText(find.byType(SearchBar), 'bea');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Beach trip'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'Beach trip'));
    await tester.pumpAndSettle();
    expect(find.text('Mountain'), findsNothing);
  });

  testWidgets('portrait lists one project per row, landscape uses a grid',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() async {
      final create = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          mediaEngineProvider.overrideWithValue(FakeMediaEngine()),
        ],
      ).read(createProjectProvider);
      await create(name: 'First');
      await create(name: 'Second');
    });

    await _pumpHome(tester, db, const Locale('en'));
    // 900 x 1200 is portrait.
    expect(
      tester.getTopLeft(find.text('First')).dy,
      isNot(tester.getTopLeft(find.text('Second')).dy),
    );

    tester.view.physicalSize = const Size(1300, 800);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('First')).dy,
      tester.getTopLeft(find.text('Second')).dy,
    );

    // A square window is a list again.
    tester.view.physicalSize = const Size(1000, 1000);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('First')).dy,
      isNot(tester.getTopLeft(find.text('Second')).dy),
    );
  });

  testWidgets('rendered videos show in Your videos', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(
      () => db.into(db.editorExports).insert(
            EditorExportsCompanion.insert(
              id: 'e1',
              projectName: 'Trip',
              path: '/videos/trip.mp4',
              width: 1080,
              height: 1920,
              fps: 30,
              durationMs: 15000,
              sizeBytes: 5 * 1024 * 1024,
              createdAtMs: 1,
              preset: 'project/standard',
            ),
          ),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _pumpHome(
      tester,
      db,
      const Locale('en'),
      library: DriftExportLibrary(db, exists: (_) => true),
    );

    expect(find.text(l10n.libraryTitle), findsOneWidget);
    expect(find.text('Trip'), findsOneWidget);
    expect(find.textContaining('5.0 MB'), findsWidgets);
  });
}
