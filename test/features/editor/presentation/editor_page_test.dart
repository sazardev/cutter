import 'dart:io';

import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/core/engine/media_engine.dart';
import 'package:cutter/core/settings/settings_store.dart';
import 'package:cutter/features/capture/domain/capture_ports.dart';
import 'package:cutter/features/capture/presentation/capture_providers.dart';
import 'package:cutter/features/editor/data/drift_media_bank.dart';
import 'package:cutter/features/editor/data/engine_media_inspector.dart';
import 'package:cutter/features/editor/presentation/clip_tools.dart';
import 'package:cutter/features/editor/presentation/editor_page.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/import_flow.dart';
import 'package:cutter/features/editor/presentation/missing_media.dart';
import 'package:cutter/features/editor/presentation/timeline/timeline_painters.dart';
import 'package:cutter/features/editor/presentation/timeline/timeline_view.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/engine/fake_media_engine.dart';

const MediaInfo _photo = MediaInfo(
  kind: EngineMediaKind.image,
  durationMs: 0,
  width: 4000,
  height: 3000,
  hasAudio: false,
  frameRate: 0,
  rotation: 0,
);

const _projectId = 'project-1';
const _clipDurationMs = 10000;

Future<void> _seedEmptyProject(AppDatabase db) {
  return db.into(db.editorProjects).insert(
        const EditorProjectsCompanion(
          id: Value(_projectId),
          name: Value('Test'),
          createdAtMs: Value(1),
          updatedAtMs: Value(1),
          canvasWidth: Value(1080),
          canvasHeight: Value(1920),
          fps: Value(30),
        ),
      );
}

Future<void> _seed(AppDatabase db, {required String layerKind}) async {
  await _seedEmptyProject(db);
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
          sourceUri: Value('/media/clip.mp4'),
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

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<FakeMediaEngine> _pumpPage(
  WidgetTester tester,
  AppDatabase db,
  Locale locale, {
  String projectId = _projectId,
  Size size = const Size(590, 900),
  List<String> picked = const [],
  Set<String> missing = const {},
  Map<String, MediaInfo>? media,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final engine = FakeMediaEngine(
    media: media ?? {'/media/new.mp4': fakeVideo},
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        mediaEngineProvider.overrideWithValue(engine),
        mediaInspectorProvider.overrideWith(
          (ref) => EngineMediaInspector(
            engine,
            ref.watch(idGeneratorProvider),
            keep: (path) async => path,
          ),
        ),
        mediaPickerProvider.overrideWithValue((context, kind) async => picked),
        fileExistsProvider.overrideWithValue((path) => !missing.contains(path)),
        ...overrides,
        // The test files only exist in the fake engine.
        mediaBankProvider.overrideWithValue(
          DriftMediaBank(db, exists: (_) => true),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: EditorPage(projectId: projectId),
      ),
    ),
  );
  await _settle(tester);
  return engine;
}

/// Taps a clip near its start: long clips reach past the screen edge.
Future<void> _tapClip(WidgetTester tester, String kindLabel) async {
  final clip = find.bySemanticsLabel(RegExp('$kindLabel, ')).first;
  await tester.tapAt(tester.getTopLeft(clip) + const Offset(24, 24));
  await _settle(tester);
}

Future<AppLocalizations> _strings(Locale locale) =>
    AppLocalizations.delegate.load(locale);

void main() {
  group('text', () {
    testWidgets('the text tool adds a text, types over it and styles it',
        (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() => _seed(db, layerKind: 'video'));
      final l10n = await _strings(const Locale('en'));
      final engine = await _pumpPage(tester, db, const Locale('en'));

      await tester.tap(find.byTooltip(l10n.addLayerAction));
      // The sheet is pushed on one frame and slides up over the next ones.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text(l10n.addLayerTextHint));
      // The sheet closes, then the text is saved.
      for (var i = 0; i < 3; i++) {
        await _settle(tester);
      }

      expect(
        engine.session!.timelines.last.layers.map((l) => l.kind),
        contains(EngineMediaKind.text),
      );
      Text? sentText() {
        final layer = engine.session!.timelines.last.layers
            .firstWhere((l) => l.kind == EngineMediaKind.text);
        return layer.clips.single.text == null
            ? null
            : Text(layer.clips.single.text!.content);
      }

      expect(sentText()!.data, l10n.textDefaultContent);

      await tester.enterText(find.byType(TextField), 'Hola mundo');
      await tester.pump(const Duration(milliseconds: 500));
      await _settle(tester);
      expect(sentText()!.data, 'Hola mundo');

      await tester.ensureVisible(find.text(l10n.textSectionFont));
      await tester.tap(find.text(l10n.textSectionFont));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(find.text('Anton'));
      await tester.tap(find.text('Anton'));
      await _settle(tester);
      final clip = engine.session!.timelines.last.layers
          .firstWhere((l) => l.kind == EngineMediaKind.text)
          .clips
          .single;
      expect(clip.text!.font, 'anton');
      expect(clip.text!.content, 'Hola mundo');
    });
  });

  for (final locale in const [Locale('en'), Locale('es')]) {
    final tag = locale.languageCode;

    testWidgets('an empty project invites to add media ($tag)', (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() => _seedEmptyProject(db));
      final l10n = await _strings(locale);

      await _pumpPage(tester, db, locale);

      expect(find.text(l10n.emptyTimelineTitle), findsOneWidget);
      expect(find.text(l10n.importMediaAction), findsOneWidget);
      expect(find.text(l10n.addMediaAction), findsOneWidget);
    });

    testWidgets('imports a picked video onto the timeline ($tag)',
        (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() => _seedEmptyProject(db));
      final l10n = await _strings(locale);
      final engine =
          await _pumpPage(tester, db, locale, picked: ['/media/new.mp4']);

      await tester.tap(find.text(l10n.importMediaAction));
      await _settle(tester);

      expect(find.byType(SnackBar), findsNothing);
      expect(find.text(l10n.emptyTimelineTitle), findsNothing);
      // The engine was given the new clip to render, and the empty project
      // took the widescreen shape of the video.
      final timeline = engine.session!.timelines.last;
      expect(timeline.layers.single.clips.single.path, '/media/new.mp4');
      expect((timeline.width, timeline.height), (1920, 1080));
    });
  }

  testWidgets('leaves out files that cannot be imported, without a notice',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() => _seedEmptyProject(db));
    final l10n = await _strings(const Locale('en'));
    await _pumpPage(
      tester,
      db,
      const Locale('en'),
      picked: ['/media/notes.txt'],
    );

    await tester.tap(find.text(l10n.importMediaAction));
    await _settle(tester);

    expect(find.byType(SnackBar), findsNothing);
    expect(find.text(l10n.emptyTimelineTitle), findsOneWidget);
  });

  testWidgets('shows a retryable error when the project cannot be read',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    final l10n = await _strings(const Locale('en'));

    await _pumpPage(tester, db, const Locale('en'), projectId: 'missing');

    expect(find.text(l10n.loadErrorTitle), findsOneWidget);
    expect(find.text(l10n.retryAction), findsOneWidget);
  });

  testWidgets('selecting a video clip shows the clip tools', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() => _seed(db, layerKind: 'video'));
    final l10n = await _strings(const Locale('en'));
    await _pumpPage(tester, db, const Locale('en'));

    await _tapClip(tester, l10n.layerKindVideo);

    // A tap shows only the short bar.
    for (final label in [
      l10n.editClipAction,
      l10n.duplicateAction,
      l10n.splitAction,
      l10n.deleteAction,
      l10n.moreActions,
    ]) {
      expect(find.byTooltip(label), findsWidgets, reason: label);
    }
    expect(find.bySemanticsLabel(l10n.filtersLabel), findsNothing);

    // More opens the full options.
    await tester.tap(find.byTooltip(l10n.moreActions));
    await _settle(tester);
    for (final label in [
      l10n.filtersLabel,
      l10n.adjustTool,
      l10n.reverseLabel,
    ]) {
      expect(find.bySemanticsLabel(label), findsWidgets, reason: label);
    }
  });

  testWidgets('a double tap on a clip opens its full options', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() => _seed(db, layerKind: 'video'));
    final l10n = await _strings(const Locale('en'));
    await _pumpPage(tester, db, const Locale('en'));

    final clip =
        find.bySemanticsLabel(RegExp('${l10n.layerKindVideo}, ')).first;
    final spot = tester.getTopLeft(clip) + const Offset(24, 24);
    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 80));
    // The first tap selected it without waiting.
    expect(find.byTooltip(l10n.moreActions), findsWidgets);
    await tester.tapAt(spot);
    await _settle(tester);

    expect(find.bySemanticsLabel(l10n.filtersLabel), findsWidgets);
  });

  testWidgets('an audio clip offers volume but no filters', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() => _seed(db, layerKind: 'audio'));
    final l10n = await _strings(const Locale('en'));
    await _pumpPage(tester, db, const Locale('en'));

    await _tapClip(tester, l10n.layerKindAudio);
    await tester.tap(find.byTooltip(l10n.moreActions));
    await _settle(tester);

    expect(find.bySemanticsLabel(l10n.volumeTool), findsOneWidget);
    expect(find.bySemanticsLabel(l10n.filtersLabel), findsNothing);
  });

  testWidgets('deleting a clip can be undone from the top bar', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() => _seed(db, layerKind: 'video'));
    final l10n = await _strings(const Locale('en'));
    await _pumpPage(tester, db, const Locale('en'));

    await _tapClip(tester, l10n.layerKindVideo);
    await tester.tap(find.byTooltip(l10n.deleteAction));
    await _settle(tester);
    expect(find.text(l10n.emptyTimelineTitle), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.undoAction));
    await _settle(tester);
    expect(find.text(l10n.emptyTimelineTitle), findsNothing);
  });

  testWidgets('the play button drives the engine preview', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() => _seed(db, layerKind: 'video'));
    final l10n = await _strings(const Locale('en'));
    final engine = await _pumpPage(tester, db, const Locale('en'));

    await tester.tap(find.byTooltip(l10n.playAction));
    await tester.pump();

    expect(engine.session!.playing, isTrue);
    expect(find.byType(Texture), findsOneWidget);
  });

  testWidgets('wide windows show a side bar that folds, and clip properties',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() => _seed(db, layerKind: 'video'));
    final l10n = await _strings(const Locale('en'));
    await _pumpPage(
      tester,
      db,
      const Locale('en'),
      size: const Size(1280, 800),
    );

    expect(find.byType(EditorRail), findsOneWidget);
    expect(find.text(l10n.addMediaAction), findsOneWidget);
    expect(tester.getSize(find.byType(EditorRail)).width, greaterThan(150));
    await tester.tap(find.byTooltip(l10n.railCollapse));
    await _settle(tester);
    expect(tester.getSize(find.byType(EditorRail)).width, lessThan(100));
    expect(find.byTooltip(l10n.railExpand), findsOneWidget);

    expect(find.byType(ClipPropertiesPanel), findsNothing);
    await _tapClip(tester, l10n.layerKindVideo);
    await tester.pump(const Duration(milliseconds: 400));
    // A tap shows the short bar over the timeline, not the side panel.
    expect(find.text(l10n.inspectorTitle), findsNothing);
    expect(find.byTooltip(l10n.moreActions), findsWidgets);
    await tester.tap(find.byTooltip(l10n.moreActions).first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(l10n.inspectorTitle), findsOneWidget);
  });

  testWidgets('the timeline moves above or beside the preview', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() => _seed(db, layerKind: 'video'));
    final l10n = await _strings(const Locale('en'));
    await _pumpPage(
      tester,
      db,
      const Locale('en'),
      size: const Size(1280, 800),
    );
    Offset timeline() => tester.getTopLeft(find.byType(TimelineView));
    Offset preview() => tester.getTopLeft(find.byType(Texture));
    expect(timeline().dy, greaterThan(preview().dy));

    await tester.tap(find.bySemanticsLabel(l10n.layoutTool));
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel(l10n.layoutTop));
    await _settle(tester);
    expect(timeline().dy, lessThan(preview().dy));

    await tester.tap(find.bySemanticsLabel(l10n.layoutSide));
    await _settle(tester);
    expect(timeline().dx, greaterThan(preview().dx));
    final saved = await tester.runAsync(
      () => SettingsStore(db).read('editor.timeline_position'),
    );
    expect(saved, 'side');
  });

  testWidgets('importing into the bank, then a tap places the file',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() => _seedEmptyProject(db));
    final l10n = await _strings(const Locale('en'));
    final engine = await _pumpPage(
      tester,
      db,
      const Locale('en'),
      picked: ['/media/new.mp4'],
    );

    await tester.tap(find.bySemanticsLabel(l10n.mediaTool));
    await _settle(tester);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text(l10n.bankEmpty), findsOneWidget);
    await tester.tap(find.byTooltip(l10n.importAction));
    await _settle(tester);

    // In the bank, not yet on the timeline.
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text(l10n.bankThisProject(1)), findsOneWidget);
    expect(find.text(l10n.emptyTimelineTitle), findsOneWidget);

    await tester.tap(
      find.bySemanticsLabel(
        RegExp(RegExp.escape(l10n.bankPlaceLabel('new.mp4'))),
      ),
    );
    await _settle(tester);
    final clips = engine.session!.timelines.last.layers.single.clips;
    expect(clips.single.path, '/media/new.mp4');
  });

  testWidgets('the format panel changes the canvas the engine renders',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() => _seed(db, layerKind: 'video'));
    final l10n = await _strings(const Locale('en'));
    final engine = await _pumpPage(tester, db, const Locale('en'));

    await tester.tap(find.bySemanticsLabel(l10n.canvasTool));
    await _settle(tester);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.bySemanticsLabel(RegExp('16:9')));
    await _settle(tester);

    final timeline = engine.session!.timelines.last;
    expect((timeline.width, timeline.height), (1920, 1080));
    final row = await tester.runAsync(
      () => db.select(db.editorProjects).getSingle(),
    );
    expect(row!.canvasWidth, 1920);
  });

  testWidgets('framing a clip sends the transform to the engine and saves it',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() => _seed(db, layerKind: 'video'));
    final l10n = await _strings(const Locale('en'));
    final engine = await _pumpPage(tester, db, const Locale('en'));

    await _tapClip(tester, l10n.layerKindVideo);
    await tester.tap(find.byTooltip(l10n.moreActions));
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel(l10n.transformTool));
    await _settle(tester);
    // The panel is a list of folded sections: open one, then use it.
    Future<void> open(String section, String item) async {
      await tester.ensureVisible(find.text(section));
      await tester.tap(find.text(section));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(find.text(item));
      await tester.tap(find.text(item));
      await _settle(tester);
    }

    await open(l10n.transformSectionFit, l10n.fillAction);
    await open(l10n.transformSectionActions, l10n.rotateAction);

    final clip = engine.session!.timelines.last.layers.single.clips.single;
    expect(clip.fill, isTrue);
    expect(clip.rotation, 90);
    final row = await tester.runAsync(
      () => db.select(db.editorClips).getSingle(),
    );
    expect((row!.fit, row.rotation), ('fill', 90.0));
  });

  testWidgets('the project is saved from the start, with a first restore point',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() => _seed(db, layerKind: 'video'));
    final l10n = await _strings(const Locale('en'));
    await _pumpPage(tester, db, const Locale('en'));
    expect(find.text(l10n.statusSaved), findsOneWidget);

    await tester.tap(find.text(l10n.statusSaved));
    await _settle(tester);
    expect(find.text(l10n.checkpointStart), findsOneWidget);
    await tester.tap(find.text(l10n.saveVersionAction));
    await _settle(tester);

    expect(find.text(l10n.statusSaved), findsOneWidget);
    expect(find.text(l10n.defaultVersionName(2)), findsWidgets);
  });

  testWidgets('tapping the name renames the project in place', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() => _seed(db, layerKind: 'video'));
    await _pumpPage(tester, db, const Locale('en'));

    await tester.tap(find.text('Test'));
    await tester.pump();
    expect(find.byType(Dialog), findsNothing);
    await tester.enterText(find.byType(TextField), 'Summer trip');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);

    expect(find.text('Summer trip'), findsOneWidget);
    final row = await tester.runAsync(
      () => db.select(db.editorProjects).getSingle(),
    );
    expect(row!.name, 'Summer trip');
  });

  testWidgets('preview mode hides the timeline and comes back', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() => _seed(db, layerKind: 'video'));
    final l10n = await _strings(const Locale('en'));
    await _pumpPage(tester, db, const Locale('en'));

    await tester.tap(find.byTooltip(l10n.previewModeAction));
    await _settle(tester);
    expect(find.byTooltip(l10n.undoAction), findsNothing);
    expect(find.byType(Slider), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.exitPreviewAction));
    await _settle(tester);
    expect(find.byTooltip(l10n.undoAction), findsOneWidget);
  });

  testWidgets('the clip editor plays only its clip and saves its speed',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() => _seed(db, layerKind: 'video'));
    final l10n = await _strings(const Locale('en'));
    final engine = await _pumpPage(tester, db, const Locale('en'));

    await _tapClip(tester, l10n.layerKindVideo);
    await tester.tap(find.byTooltip(l10n.editClipAction));
    await _settle(tester);
    await _settle(tester);
    expect(find.text(l10n.studioVideoTitle), findsOneWidget);

    await tester.tap(find.text('2×'));
    await _settle(tester);

    final clip = engine.session!.timelines.last.layers.single.clips.single;
    expect((clip.startMs, clip.speed), (0, 2.0));
    final row = await tester.runAsync(
      () => db.select(db.editorClips).getSingle(),
    );
    expect(row!.speed, 2.0);

    await tester.tap(find.widgetWithText(FilledButton, l10n.doneAction));
    await _settle(tester);
    // Let the page transition finish.
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text(l10n.studioVideoTitle), findsNothing);
  });

  testWidgets('export offers platforms and qualities with a size estimate',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() => _seed(db, layerKind: 'video'));
    final l10n = await _strings(const Locale('en'));
    await _pumpPage(tester, db, const Locale('en'));

    await tester.tap(find.text(l10n.exportAction).first);
    await _settle(tester);
    await tester.tap(find.text(l10n.platformWidescreen));
    await _settle(tester);

    expect(find.textContaining('1920 × 1080'), findsOneWidget);
    expect(find.text(l10n.exportReframedNote), findsOneWidget);
  });

  testWidgets('dragging the end handle trims by the distance dragged',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() => _seed(db, layerKind: 'video'));
    final l10n = await _strings(const Locale('en'));
    await _pumpPage(tester, db, const Locale('en'));
    await _tapClip(tester, l10n.layerKindVideo);
    await tester.tap(find.byTooltip(l10n.editClipAction));
    await _settle(tester);
    await _settle(tester);

    final handle = find.bySemanticsLabel(l10n.trimEndHandle);
    await tester.drag(handle, const Offset(-60, 0));
    await _settle(tester);

    final row = await tester.runAsync(
      () => db.select(db.editorClips).getSingle(),
    );
    // The bar shows 10 s plus 10 s of context; 60 px of a ~560 px bar is
    // roughly 2 s, never the whole clip.
    expect(row!.outPointMs, inInclusiveRange(6000, 9500));
  });

  testWidgets('a trim handle stops at the next clip', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() async {
      await _seed(db, layerKind: 'video');
      await db.into(db.editorClips).insert(
            const EditorClipsCompanion(
              id: Value('clip-2'),
              layerId: Value('layer-1'),
              sortKey: Value(1),
              sourceUri: Value('/media/clip.mp4'),
              startMs: Value(11000),
              durationMs: Value(2000),
              inPointMs: Value(0),
              outPointMs: Value(2000),
              reversed: Value(false),
              volume: Value(1),
              filterId: Value(null),
              adjustmentsJson: Value('{}'),
            ),
          );
      // The first clip's source is longer than what it plays.
      await (db.update(db.editorClips)..where((c) => c.id.equals('clip-1')))
          .write(const EditorClipsCompanion(sourceDurationMs: Value(30000)));
    });
    final l10n = await _strings(const Locale('en'));
    await _pumpPage(tester, db, const Locale('en'));
    await _tapClip(tester, l10n.layerKindVideo);
    await tester.tap(find.byTooltip(l10n.editClipAction));
    await _settle(tester);
    await _settle(tester);

    await tester.drag(
      find.bySemanticsLabel(l10n.trimEndHandle),
      const Offset(400, 0),
    );
    await _settle(tester);

    final first = await tester.runAsync(
      () => (db.select(db.editorClips)..where((c) => c.id.equals('clip-1')))
          .getSingle(),
    );
    // There is 1 s of room before clip-2.
    expect(first!.outPointMs, 11000);
    expect(find.byType(SnackBar), findsNothing);
  });

  group('direct manipulation in the preview', () {
    Future<(FakeMediaEngine, AppDatabase)> openWithPicture(
      WidgetTester tester,
    ) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() async {
        await _seed(db, layerKind: 'video');
        await (db.update(db.editorClips)..where((c) => c.id.equals('clip-1')))
            .write(
          const EditorClipsCompanion(
            sourceWidth: Value(1920),
            sourceHeight: Value(1080),
          ),
        );
      });
      final engine = await _pumpPage(tester, db, const Locale('en'));
      return (engine, db);
    }

    testWidgets('a tap on the picture never plays or pauses', (tester) async {
      final (engine, _) = await openWithPicture(tester);

      await tester.tapAt(tester.getRect(find.byType(Texture)).center);
      await _settle(tester);
      await tester.tapAt(
        tester.getRect(find.byType(Texture)).topLeft + const Offset(4, 4),
      );
      await _settle(tester);

      expect(engine.session!.playing, isFalse);
    });

    testWidgets('dragging a picture selects it and moves it in one motion',
        (tester) async {
      final (_, db) = await openWithPicture(tester);
      final rect = tester.getRect(find.byType(Texture));

      await tester.dragFrom(rect.center, Offset(rect.width * 0.2, 0));
      await _settle(tester);

      final row = await tester.runAsync(
        () => db.select(db.editorClips).getSingle(),
      );
      expect(row!.posX, greaterThan(0.1));
    });

    testWidgets('a corner handle scales the picture', (tester) async {
      final (_, db) = await openWithPicture(tester);
      final l10n = await _strings(const Locale('en'));
      await _tapClip(tester, l10n.layerKindVideo);
      final rect = tester.getRect(find.byType(Texture));
      // 1920x1080 on a 1080x1920 canvas fits at the full width, so the
      // bottom right corner sits on the right edge, kept inside by the inset.
      final k = rect.width / 1080;
      final corner = Offset(rect.right - 18, rect.center.dy + 303.75 * k);

      await tester.dragFrom(corner, (corner - rect.center) * 0.5);
      await _settle(tester);

      final row = await tester.runAsync(
        () => db.select(db.editorClips).getSingle(),
      );
      expect(row!.scale, greaterThan(1.15));
    });

    testWidgets('the rotate handle turns the picture', (tester) async {
      final (_, db) = await openWithPicture(tester);
      final l10n = await _strings(const Locale('en'));
      await _tapClip(tester, l10n.layerKindVideo);
      final rect = tester.getRect(find.byType(Texture));
      final k = rect.width / 1080;
      final handle = Offset(rect.center.dx, rect.center.dy - 303.75 * k - 36);

      // A quarter turn clockwise: from above the picture to its right.
      await tester.dragFrom(handle, const Offset(120, 120));
      await _settle(tester);

      final row = await tester.runAsync(
        () => db.select(db.editorClips).getSingle(),
      );
      expect(row!.rotation, isNot(0));
    });
  });

  testWidgets('the layer button puts the media on a new layer of its kind',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() => _seed(db, layerKind: 'video'));
    final l10n = await _strings(const Locale('en'));
    final engine = await _pumpPage(
      tester,
      db,
      const Locale('en'),
      picked: ['/media/new.mp4'],
    );

    await tester.tap(find.byTooltip(l10n.addLayerAction));
    await _settle(tester);
    // The menu asks which kind of layer first.
    expect(find.text(l10n.addLayerTitle), findsOneWidget);
    await tester.tap(find.text(l10n.addLayerVideoHint));
    await _settle(tester);

    final layers = engine.session!.timelines.last.layers;
    expect(layers, hasLength(2));
    expect(layers.first.clips.single.path, '/media/new.mp4');
  });

  testWidgets('a long press lifts a layer and dragging puts it above another',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() async {
      await _seed(db, layerKind: 'video');
      await db.into(db.editorLayers).insert(
            const EditorLayersCompanion(
              id: Value('layer-2'),
              projectId: Value(_projectId),
              position: Value(1),
              kind: Value('audio'),
              volume: Value(1),
              muted: Value(false),
            ),
          );
      await db.into(db.editorClips).insert(
            const EditorClipsCompanion(
              id: Value('clip-2'),
              layerId: Value('layer-2'),
              sortKey: Value(0),
              sourceUri: Value('/media/song.mp3'),
              startMs: Value(0),
              durationMs: Value(4000),
              inPointMs: Value(0),
              outPointMs: Value(4000),
              reversed: Value(false),
              volume: Value(1),
              filterId: Value(null),
              adjustmentsJson: Value('{}'),
            ),
          );
    });
    final l10n = await _strings(const Locale('en'));
    await _pumpPage(tester, db, const Locale('en'));

    final header = find.byTooltip(l10n.muteLayerAction).last;
    final gesture = await tester.startGesture(tester.getCenter(header));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    await gesture.up();
    await _settle(tester);

    final rows = await tester.runAsync(
      () => (db.select(db.editorLayers)
            ..orderBy([(l) => OrderingTerm.asc(l.position)]))
          .get(),
    );
    expect(rows!.map((l) => l.id), ['layer-2', 'layer-1']);
  });

  group('timeline panning', () {
    Future<ScrollableState> pumpAndFindTrackScroller(
      WidgetTester tester,
      AppDatabase db,
    ) async {
      await _pumpPage(tester, db, const Locale('en'));
      final horizontal = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.right,
      );
      return tester.state<ScrollableState>(horizontal.first);
    }

    testWidgets('a mouse or trackpad can drag the timeline sideways',
        (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() => _seed(db, layerKind: 'video'));
      final scroller = await pumpAndFindTrackScroller(tester, db);

      final devices = ScrollConfiguration.of(scroller.context).dragDevices;
      expect(devices, contains(PointerDeviceKind.mouse));
      expect(devices, contains(PointerDeviceKind.trackpad));
    });

    testWidgets('the wheel over the ruler scrolls the timeline sideways',
        (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() => _seed(db, layerKind: 'video'));
      final scroller = await pumpAndFindTrackScroller(tester, db);
      expect(scroller.position.pixels, 0);

      final ruler = tester.getCenter(
        find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter is RulerPainter,
        ),
      );
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(ruler));
      // The wheel turns vertically, the timeline moves horizontally.
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
      await tester.pump();

      expect(scroller.position.pixels, 120);

      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -500)));
      await tester.pump();
      expect(scroller.position.pixels, 0);
    });
  });

  group('the divider between preview and timeline', () {
    Future<AppDatabase> open(WidgetTester tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() => _seed(db, layerKind: 'video'));
      await _pumpPage(
        tester,
        db,
        const Locale('en'),
        size: const Size(1280, 800),
      );
      return db;
    }

    Future<String?> stored(WidgetTester tester, AppDatabase db) async {
      final value = await tester.runAsync(
        () => SettingsStore(db).read('editor.preview_share'),
      );
      return value;
    }

    testWidgets('dragging it gives the preview more room and is remembered',
        (tester) async {
      final db = await open(tester);
      final l10n = await _strings(const Locale('en'));
      final before = tester.getSize(find.byType(Texture)).height;

      final divider = find.bySemanticsLabel(l10n.splitHandleLabel);
      await tester.drag(divider, const Offset(0, 120));
      await _settle(tester);

      expect(tester.getSize(find.byType(Texture)).height, greaterThan(before));
      expect(double.parse((await stored(tester, db))!), greaterThan(0.58));
    });

    testWidgets(
        'the button focuses the preview, then the timeline, then '
        'shows both', (tester) async {
      final db = await open(tester);
      final l10n = await _strings(const Locale('en'));

      await tester.tap(find.byTooltip(l10n.splitFocusPreview));
      await _settle(tester);
      expect(await stored(tester, db), '1.000');
      final pane = find
          .ancestor(
            of: find.byType(TimelineView),
            matching: find.byType(ClipRect),
          )
          .first;
      expect(tester.getSize(pane).height, lessThan(1));

      await tester.tap(find.byTooltip(l10n.splitFocusTimeline));
      await _settle(tester);
      expect(await stored(tester, db), '0.000');
      // The play button stays within reach while the timeline is focused.
      expect(find.byTooltip(l10n.playAction), findsOneWidget);

      await tester.tap(find.byTooltip(l10n.splitBalance));
      await _settle(tester);
      expect(await stored(tester, db), '0.580');
    });

    testWidgets('the time scale menu zooms to seconds, milliseconds and fit',
        (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() => _seed(db, layerKind: 'video'));
      final l10n = await _strings(const Locale('en'));
      await _pumpPage(tester, db, const Locale('en'));

      // The default view marks every second.
      expect(find.text(l10n.timeUnitSeconds(1)), findsWidgets);

      Future<void> pick(String item) async {
        await tester.tap(find.byTooltip(l10n.timeScaleTitle).first);
        await tester.pumpAndSettle();
        // The menu row takes the tap; its text is only laid over it.
        await tester.tap(find.text(item), warnIfMissed: false);
        await tester.pumpAndSettle();
      }

      await pick(l10n.timeScaleMilliseconds);
      expect(find.text(l10n.timeUnitMilliseconds(50)), findsWidgets);

      await pick(l10n.timeScaleMinutes);
      expect(find.text(l10n.timeUnitMinutes(1)), findsWidgets);

      // Fit: the 10 s clip fills the view, so marks come every second or two.
      await pick(l10n.timeScaleFit);
      expect(find.text(l10n.timeUnitMinutes(1)), findsNothing);
    });
  });

  group('missing media', () {
    testWidgets('a clip whose file is gone is flagged and can be relinked',
        (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() => _seed(db, layerKind: 'video'));
      final l10n = await _strings(const Locale('en'));
      await _pumpPage(
        tester,
        db,
        const Locale('en'),
        picked: const ['/media/new.mp4'],
        missing: const {'/media/clip.mp4'},
        media: {
          '/media/new.mp4': const MediaInfo(
            kind: EngineMediaKind.video,
            durationMs: 20000,
            width: 1920,
            height: 1080,
            hasAudio: true,
            frameRate: 30,
            rotation: 0,
          ),
        },
      );

      expect(find.text(l10n.missingMediaBanner(1)), findsOneWidget);

      await tester.tap(find.text(l10n.missingMediaFind));
      await _settle(tester);
      await _settle(tester);

      final row = await tester.runAsync(
        () => db.select(db.editorClips).getSingle(),
      );
      expect(row!.sourceUri, '/media/new.mp4');
      expect(find.text(l10n.missingMediaBanner(1)), findsNothing);
    });

    testWidgets('a file shorter than the clips is refused with a reason',
        (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() => _seed(db, layerKind: 'video'));
      final l10n = await _strings(const Locale('en'));
      // The fake file lasts 4 s; the clip needs 10 s.
      await _pumpPage(
        tester,
        db,
        const Locale('en'),
        picked: const ['/media/new.mp4'],
        missing: const {'/media/clip.mp4'},
      );

      await tester.tap(find.text(l10n.missingMediaFind));
      await _settle(tester);
      await tester.pumpAndSettle();

      expect(find.text(l10n.relinkTooShort), findsOneWidget);
      final row = await tester.runAsync(
        () => db.select(db.editorClips).getSingle(),
      );
      expect(row!.sourceUri, '/media/clip.mp4');
    });

    testWidgets('with every file present there is no banner', (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() => _seed(db, layerKind: 'video'));
      final l10n = await _strings(const Locale('en'));
      await _pumpPage(tester, db, const Locale('en'));

      expect(find.text(l10n.missingMediaFind), findsNothing);
    });
  });

  group('capture', () {
    Future<void> openCapture(WidgetTester tester, AppLocalizations l10n) async {
      await tester.tap(find.text(l10n.captureTool).first);
      await tester.pumpAndSettle();
    }

    testWidgets('a photo from the camera lands on the timeline',
        (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() => _seedEmptyProject(db));
      final l10n = await _strings(const Locale('en'));
      await _pumpPage(
        tester,
        db,
        const Locale('en'),
        size: const Size(1200, 900),
        media: {'/camera/photo.jpg': _photo},
        overrides: [
          captureAvailableProvider.overrideWithValue(true),
          cameraCaptureProvider
              .overrideWithValue(_FakeCamera('/camera/photo.jpg')),
        ],
      );
      await openCapture(tester, l10n);

      await tester.tap(find.text(l10n.capturePhoto));
      await _settle(tester);
      await _settle(tester);

      final clips = await tester.runAsync(
        () => db.select(db.editorClips).get(),
      );
      expect(clips!.single.sourceUri, '/camera/photo.jpg');
    });

    testWidgets('a denied camera explains how to allow it', (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() => _seedEmptyProject(db));
      final l10n = await _strings(const Locale('en'));
      await _pumpPage(
        tester,
        db,
        const Locale('en'),
        size: const Size(1200, 900),
        overrides: [
          captureAvailableProvider.overrideWithValue(true),
          cameraCaptureProvider
              .overrideWithValue(_FakeCamera(null, denied: true)),
        ],
      );
      await openCapture(tester, l10n);

      await tester.tap(find.text(l10n.captureVideo));
      await _settle(tester);
      await tester.pumpAndSettle();

      expect(find.text(l10n.captureCameraDeniedTitle), findsOneWidget);
      expect(find.text(l10n.settingsPermissionsOpenSettings), findsOneWidget);
    });

    testWidgets('a voice recording is added as a sound clip', (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      final dir = Directory.systemTemp.createTempSync('cutter_capture_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/voice.m4a';
      await tester.runAsync(() => _seedEmptyProject(db));
      final l10n = await _strings(const Locale('en'));
      await _pumpPage(
        tester,
        db,
        const Locale('en'),
        size: const Size(1200, 900),
        media: {path: fakeSound},
        overrides: [
          captureAvailableProvider.overrideWithValue(true),
          voiceRecorderFactoryProvider.overrideWithValue(_FakeVoice.new),
          voiceFilePathProvider.overrideWithValue(() async => path),
        ],
      );
      await openCapture(tester, l10n);

      await tester.tap(find.text(l10n.captureVoice));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Recording'), findsOneWidget);

      await tester.tap(find.text(l10n.captureVoiceStop));
      await _settle(tester);
      await _settle(tester);

      final layers = await tester.runAsync(
        () => db.select(db.editorLayers).get(),
      );
      expect(layers!.map((l) => l.kind), ['audio']);
    });

    testWidgets('a denied microphone records nothing and says why',
        (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() => _seedEmptyProject(db));
      final l10n = await _strings(const Locale('en'));
      await _pumpPage(
        tester,
        db,
        const Locale('en'),
        size: const Size(1200, 900),
        overrides: [
          captureAvailableProvider.overrideWithValue(true),
          voiceRecorderFactoryProvider
              .overrideWithValue(() => _FakeVoice(allowed: false)),
        ],
      );
      await openCapture(tester, l10n);

      await tester.tap(find.text(l10n.captureVoice));
      await tester.pumpAndSettle();

      expect(find.text(l10n.captureMicDeniedTitle), findsOneWidget);
      expect(find.text(l10n.captureVoiceStop), findsNothing);
    });

    testWidgets('on a device without camera or microphone there is no tool',
        (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() => _seedEmptyProject(db));
      final l10n = await _strings(const Locale('en'));
      await _pumpPage(
        tester,
        db,
        const Locale('en'),
        size: const Size(1200, 900),
        overrides: [captureAvailableProvider.overrideWithValue(false)],
      );

      expect(find.text(l10n.captureTool), findsNothing);
      expect(find.text(l10n.mediaTool), findsWidgets);
    });
  });

  group('animation presets', () {
    Future<void> openPresets(
      WidgetTester tester,
      AppLocalizations l10n,
    ) async {
      await _tapClip(tester, l10n.layerKindVideo);
      await tester.tap(find.byTooltip(l10n.moreActions));
      await _settle(tester);
      final section = find.widgetWithText(
        ExpansionTile,
        l10n.animationPresetsTitle,
      );
      await tester.ensureVisible(section);
      await tester.pumpAndSettle();
      await tester.tap(section);
      await tester.pumpAndSettle();
    }

    Future<void> tapText(WidgetTester tester, String text) async {
      final target = find.text(text);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
    }

    Future<void> seedTwoClips(AppDatabase db) async {
      await _seed(db, layerKind: 'video');
      await db.into(db.editorClips).insert(
            const EditorClipsCompanion(
              id: Value('clip-2'),
              layerId: Value('layer-1'),
              sortKey: Value(1),
              sourceUri: Value('/media/clip.mp4'),
              startMs: Value(11000),
              durationMs: Value(2000),
              inPointMs: Value(0),
              outPointMs: Value(2000),
              reversed: Value(false),
              volume: Value(1),
              filterId: Value(null),
              adjustmentsJson: Value('{}'),
            ),
          );
    }

    testWidgets('a preset sets both sides of the selected clip',
        (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() => _seed(db, layerKind: 'video'));
      final l10n = await _strings(const Locale('en'));
      await _pumpPage(
        tester,
        db,
        const Locale('en'),
        size: const Size(1200, 1800),
      );
      await openPresets(tester, l10n);

      await tapText(tester, l10n.animationPresetZoom);
      await _settle(tester);

      final row = await tester.runAsync(
        () => db.select(db.editorClips).getSingle(),
      );
      expect(row!.animIn, 'zoom_in');
      expect(row.animInMs, 700);
      expect(row.animOut, 'zoom_out');
      expect(row.animOutMs, 500);

      await tapText(tester, l10n.animationPresetNone);
      await _settle(tester);
      final cleared = await tester.runAsync(
        () => db.select(db.editorClips).getSingle(),
      );
      expect(cleared!.animIn, isNull);
      expect(cleared.animOut, isNull);
    });

    testWidgets('the switch gives the preset to every clip of the layer',
        (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() => seedTwoClips(db));
      final l10n = await _strings(const Locale('en'));
      await _pumpPage(
        tester,
        db,
        const Locale('en'),
        size: const Size(1200, 1800),
      );
      await openPresets(tester, l10n);

      await tapText(tester, l10n.animationPresetWholeLayer);
      await tester.pump();
      await tapText(tester, l10n.animationPresetPop);
      await _settle(tester);

      final rows = await tester.runAsync(
        () => db.select(db.editorClips).get(),
      );
      expect(rows!.map((r) => r.animIn), ['pop', 'pop']);
    });

    testWidgets('an animation can be saved as a preset, used and deleted',
        (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() => _seed(db, layerKind: 'video'));
      final l10n = await _strings(const Locale('en'));
      await _pumpPage(
        tester,
        db,
        const Locale('en'),
        size: const Size(1200, 1800),
      );
      await openPresets(tester, l10n);

      // Nothing to save before the clip animates.
      await tapText(tester, l10n.animationPresetSave);
      await tester.pumpAndSettle();
      expect(find.text(l10n.animationPresetNeedsAnimation), findsOneWidget);
      await tapText(tester, l10n.importReportClose);
      await tester.pumpAndSettle();

      await tapText(tester, l10n.animationPresetSpin);
      await _settle(tester);
      await tapText(tester, l10n.animationPresetSave);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'My spin');
      await tapText(tester, l10n.animationPresetSaveConfirm);
      await _settle(tester);
      await tester.pumpAndSettle();

      expect(find.text(l10n.animationPresetYours), findsOneWidget);
      expect(find.text('My spin'), findsOneWidget);

      await tester.tap(find.byTooltip(l10n.animationPresetDelete));
      await _settle(tester);
      await tester.pumpAndSettle();
      expect(find.text('My spin'), findsNothing);
    });
  });

  group('transitions', () {
    Future<void> seedJoined(AppDatabase db) async {
      await _seed(db, layerKind: 'video');
      await db.into(db.editorClips).insert(
            const EditorClipsCompanion(
              id: Value('clip-2'),
              layerId: Value('layer-1'),
              sortKey: Value(1),
              sourceUri: Value('/media/clip.mp4'),
              startMs: Value(10000),
              durationMs: Value(4000),
              inPointMs: Value(0),
              outPointMs: Value(4000),
              reversed: Value(false),
              volume: Value(1),
              filterId: Value(null),
              adjustmentsJson: Value('{}'),
            ),
          );
    }

    Future<void> openTransition(
      WidgetTester tester,
      AppLocalizations l10n, {
      required bool second,
    }) async {
      final clips = find.bySemanticsLabel(RegExp('${l10n.layerKindVideo}, '));
      final clip = second ? clips.last : clips.first;
      await tester.ensureVisible(clip);
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getTopLeft(clip) + const Offset(24, 24));
      await _settle(tester);
      await tester.tap(find.byTooltip(l10n.moreActions));
      await _settle(tester);
      final section = find.widgetWithText(
        ExpansionTile,
        l10n.transitionTitle,
      );
      await tester.ensureVisible(section);
      await tester.pumpAndSettle();
      await tester.tap(section);
      await tester.pumpAndSettle();
    }

    testWidgets('joins the selected clip to the one before it', (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() => seedJoined(db));
      final l10n = await _strings(const Locale('en'));
      await _pumpPage(
        tester,
        db,
        const Locale('en'),
        size: const Size(1800, 1800),
      );
      await openTransition(tester, l10n, second: true);

      final push = find.text(l10n.transitionPushLeft);
      await tester.ensureVisible(push);
      await tester.pumpAndSettle();
      await tester.tap(push);
      await _settle(tester);

      final rows = await tester.runAsync(
        () => (db.select(db.editorClips)
              ..orderBy([(c) => OrderingTerm.asc(c.startMs)]))
            .get(),
      );
      expect(rows![0].animOut, 'slide_left');
      expect(rows[0].animOutMs, 600);
      expect(rows[1].animIn, 'slide_right');
      expect(rows[1].animInMs, 600);

      final none = find.text(l10n.transitionNone);
      await tester.ensureVisible(none);
      await tester.pumpAndSettle();
      await tester.tap(none);
      await _settle(tester);
      final cleared = await tester.runAsync(
        () => (db.select(db.editorClips)
              ..orderBy([(c) => OrderingTerm.asc(c.startMs)]))
            .get(),
      );
      expect(cleared![0].animOut, isNull);
      expect(cleared[1].animIn, isNull);
    });

    testWidgets('the first clip of a layer explains what is needed',
        (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() => seedJoined(db));
      final l10n = await _strings(const Locale('en'));
      await _pumpPage(
        tester,
        db,
        const Locale('en'),
        size: const Size(1800, 1800),
      );
      await openTransition(tester, l10n, second: false);

      expect(find.text(l10n.transitionNeedsNeighbour), findsWidgets);
      expect(find.text(l10n.transitionPushLeft), findsNothing);
    });
  });
}

class _FakeCamera implements CameraCapture {
  _FakeCamera(this.path, {this.denied = false});

  final String? path;
  final bool denied;

  @override
  Future<String?> photo() async {
    if (denied) throw const CameraDenied();
    return path;
  }

  @override
  Future<String?> video() async {
    if (denied) throw const CameraDenied();
    return path;
  }

  @override
  Future<String?> lostCapture() async => null;
}

class _FakeVoice implements VoiceRecorder {
  _FakeVoice({this.allowed = true});

  final bool allowed;
  String? _path;

  @override
  Future<bool> requestPermission() async => allowed;

  @override
  Future<void> start(String path) async {
    _path = path;
    File(path).writeAsStringSync('audio');
  }

  @override
  Future<String?> stop() async => _path;

  @override
  Future<bool> get isRecording async => _path != null;

  @override
  Future<void> dispose() async {}
}
