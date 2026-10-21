import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/features/editor/presentation/editor_page.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/timeline_view.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _projectId = 'project-1';
const _clipDurationMs = 10000;

Future<void> _seed(AppDatabase db, {required String layerKind}) async {
  await db.into(db.editorProjects).insert(
        const EditorProjectsCompanion(
          id: Value(_projectId),
          name: Value('Test'),
          createdAtMs: Value(1),
          updatedAtMs: Value(1),
          canvasWidth: Value(1920),
          canvasHeight: Value(1080),
          fps: Value(60),
        ),
      );
  await db.into(db.editorLayers).insert(
        EditorLayersCompanion(
          id: const Value('layer-1'),
          projectId: const Value(_projectId),
          position: const Value(0),
          kind: Value(layerKind),
          volume: const Value(1),
          muted: const Value(false),
        ),
      );
  await db.into(db.editorClips).insert(
        const EditorClipsCompanion(
          id: Value('clip-1'),
          layerId: Value('layer-1'),
          sortKey: Value(0),
          sourceUri: Value('file:///clip.mp4'),
          startMs: Value(0),
          durationMs: Value(_clipDurationMs),
          inPointMs: Value(0),
          outPointMs: Value(_clipDurationMs),
          reversed: Value(false),
          volume: Value(1),
          filterId: Value(null),
          adjustmentsJson: Value('{}'),
        ),
      );
}

Future<void> _pumpPage(
  WidgetTester tester,
  AppDatabase db,
  Locale locale, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ...overrides,
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const EditorPage(),
      ),
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<AppLocalizations> _strings(Locale locale) =>
    AppLocalizations.delegate.load(locale);

void main() {
  const locales = [Locale('en'), Locale('es')];

  for (final locale in locales) {
    final tag = locale.languageCode;

    testWidgets('shows the empty state without a project ($tag)',
        (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      final l10n = await _strings(locale);

      await _pumpPage(tester, db, locale);

      expect(find.text(l10n.emptyTitle), findsOneWidget);
      expect(find.text(l10n.emptyBody), findsOneWidget);
      expect(find.byType(TimelineView), findsNothing);
    });

    testWidgets(
        'shows the timeline and disabled split without selection ($tag)',
        (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() => _seed(db, layerKind: 'video'));
      final l10n = await _strings(locale);

      await _pumpPage(tester, db, locale);

      expect(find.byType(TimelineView), findsOneWidget);
      expect(find.text(l10n.selectClipHint), findsOneWidget);
      expect(find.text(l10n.emptyTitle), findsNothing);
    });
  }

  testWidgets('shows a retryable error when the project cannot be read',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    const locale = Locale('en');
    final l10n = await _strings(locale);

    // The provider names a project the database does not hold, so loading it
    // fails the way an unreadable file does.
    await _pumpPage(
      tester,
      db,
      locale,
      overrides: [
        editorProjectProvider.overrideWith((ref) async => 'missing-project'),
      ],
    );

    expect(find.text(l10n.loadErrorTitle), findsOneWidget);
    expect(find.text(l10n.loadErrorBody), findsOneWidget);
    expect(find.text(l10n.retryAction), findsOneWidget);
  });

  testWidgets('disables filter chips for a selected audio clip',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() => _seed(db, layerKind: 'audio'));
    const locale = Locale('en');
    final l10n = await _strings(locale);

    await _pumpPage(tester, db, locale);
    final origin = tester.getTopLeft(find.byType(TimelineView));
    await tester.tapAt(origin + const Offset(60, 76));
    await tester.pump();

    expect(find.text(l10n.selectClipHint), findsNothing);
    final chip = find.ancestor(
      of: find.text(l10n.filterNone),
      matching: find.byWidgetPredicate(
        (widget) => widget is ChoiceChip || widget is FilterChip,
      ),
    );
    expect(chip, findsOneWidget);
    final widget = tester.widget(chip);
    final onSelected = widget is ChoiceChip
        ? widget.onSelected
        : (widget as FilterChip).onSelected;
    expect(onSelected, isNull);
  });

  testWidgets('exposes the clip as a selectable semantics node',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() => _seed(db, layerKind: 'video'));
    const locale = Locale('en');
    // The handle has to be released inside the test body: the framework
    // checks for leaked handles before the tear-down callbacks run.
    final handle = tester.ensureSemantics();

    await _pumpPage(tester, db, locale);

    final origin = tester.getTopLeft(find.byType(TimelineView));
    await tester.tapAt(origin + const Offset(60, 76));
    await tester.pump();

    final selectedNodes = find.descendant(
      of: find.byType(TimelineView),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && (widget.properties.selected ?? false),
      ),
    );
    expect(selectedNodes, findsWidgets);

    handle.dispose();
  });
}
