import 'dart:io';

import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/core/engine/media_engine.dart';
import 'package:cutter/features/editor/data/media_library.dart';
import 'package:cutter/features/editor/domain/clip_drawing.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/presentation/drawing/drawing_page.dart';
import 'package:cutter/features/editor/presentation/editor_controller.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../core/engine/fake_media_engine.dart';

const _ink = ClipDrawing([
  DrawingStroke(color: 0xFFE53935, width: 0.05, points: [0.1, 0.5, 0.9, 0.5]),
]);

void main() {
  late AppDatabase database;
  late ProviderContainer container;
  late Directory root;

  EditorController controller() =>
      container.read(editorControllerProvider.notifier);

  EditorUiState ui() => container.read(editorControllerProvider).requireValue;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('cutter-drawing-');
    database = AppDatabase.inMemory();
    await database.into(database.editorProjects).insert(
          const EditorProjectsCompanion(
            id: Value('p1'),
            name: Value('Drawing'),
            createdAtMs: Value(0),
            updatedAtMs: Value(0),
            canvasWidth: Value(1080),
            canvasHeight: Value(1920),
            fps: Value(30),
          ),
        );
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        mediaEngineProvider.overrideWithValue(FakeMediaEngine(media: const {})),
        mediaLibraryProvider.overrideWith(
          (ref) async => MediaLibrary(root: root, volatileRoots: const []),
        ),
      ],
    )..listen(editorControllerProvider, (_, __) {});
    await controller().load('p1');
  });

  tearDown(() async {
    container.dispose();
    await database.close();
    root.deleteSync(recursive: true);
  });

  // Rendering and writing the picture are real work, which the test clock
  // does not move: let real time pass between frames.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('controller', () {
    testWidgets('adding a drawing writes its PNG and selects the clip',
        (tester) async {
      final id =
          await tester.runAsync(() => controller().addDrawing(_ink, 700));

      expect(id, isNotNull);
      final clip = ui().project.clipById(id!)!;
      expect(clip.drawing, _ink);
      expect(clip.kind, MediaKind.image);
      expect(clip.startMs, 700);
      expect(ui().selectedClipId, id);
      // The picture is the canvas shape, no larger than 1920 px.
      expect((clip.sourceWidth, clip.sourceHeight), (1080, 1920));
      final file = File(clip.sourceUri);
      expect(file.existsSync(), isTrue);
      expect(file.readAsBytesSync().sublist(1, 4), [0x50, 0x4E, 0x47]);
    });

    testWidgets('a blank drawing adds nothing', (tester) async {
      final id = await tester.runAsync(
        () => controller().addDrawing(ClipDrawing.empty, 0),
      );

      expect(id, isNull);
      expect(ui().project.layers, isEmpty);
    });

    testWidgets('editing swaps the picture and undo restores it',
        (tester) async {
      final id =
          (await tester.runAsync(() => controller().addDrawing(_ink, 0)))!;
      final firstFile = ui().project.clipById(id)!.sourceUri;
      const other = ClipDrawing([
        DrawingStroke(
          color: 0xFF1E88E5,
          width: 0.04,
          points: [0.5, 0.1, 0.5, 0.9],
        ),
      ]);

      final ok =
          await tester.runAsync(() => controller().setDrawing(id, other));

      expect(ok, isTrue);
      final edited = ui().project.clipById(id)!;
      expect(edited.drawing, other);
      expect(edited.sourceUri, isNot(firstFile));
      expect(File(edited.sourceUri).existsSync(), isTrue);

      await controller().undo();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(ui().project.clipById(id)!.sourceUri, firstFile);
    });
  });

  group('screen', () {
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => openDrawing(context, startMs: 250),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('a stroke and Done put a drawing on the timeline',
        (tester) async {
      await open(tester);

      await tester.drag(find.byKey(drawingCanvasKey), const Offset(0, 120));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await settle(tester);
      await tester.pumpAndSettle();

      final clips = [for (final l in ui().project.layers) ...l.clips];
      expect(clips, hasLength(1));
      expect(clips.single.drawing!.strokes, hasLength(1));
      expect(clips.single.startMs, 250);
      expect(find.text('Draw'), findsNothing, reason: 'the screen closed');
    });

    testWidgets('Done without drawing adds nothing', (tester) async {
      await open(tester);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(ui().project.layers, isEmpty);
    });

    testWidgets('undo takes off the last stroke', (tester) async {
      await open(tester);

      await tester.drag(find.byKey(drawingCanvasKey), const Offset(0, 80));
      await tester.pump();
      final undo = find.widgetWithIcon(IconButton, Icons.undo);
      expect(tester.widget<IconButton>(undo).onPressed, isNotNull);

      await tester.tap(undo);
      await tester.pump();

      expect(tester.widget<IconButton>(undo).onPressed, isNull);
    });

    testWidgets('editing a drawing starts from its strokes', (tester) async {
      final id =
          (await tester.runAsync(() => controller().addDrawing(_ink, 0)))!;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => openDrawing(context, clipId: id),
                child: const Text('edit'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('edit'));
      await tester.pumpAndSettle();

      final undo = find.widgetWithIcon(IconButton, Icons.undo);
      expect(tester.widget<IconButton>(undo).onPressed, isNotNull);
    });
  });
}
