import 'dart:io';

import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/core/engine/media_engine.dart';
import 'package:cutter/features/editor/data/media_library.dart';
import 'package:cutter/features/editor/presentation/editor_controller.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/engine/fake_media_engine.dart';

void main() {
  late AppDatabase database;
  late ProviderContainer container;
  late FakeMediaEngine engine;
  late Directory root;

  EditorController controller() =>
      container.read(editorControllerProvider.notifier);

  setUp(() async {
    root = Directory.systemTemp.createTempSync('cutter-cutout-');
    database = AppDatabase.inMemory();
    await database.into(database.editorProjects).insert(
          const EditorProjectsCompanion(
            id: Value('p1'),
            name: Value('Photos'),
            createdAtMs: Value(0),
            updatedAtMs: Value(0),
            canvasWidth: Value(1080),
            canvasHeight: Value(1920),
            fps: Value(30),
          ),
        );
    await database.into(database.editorLayers).insert(
          const EditorLayersCompanion(
            id: Value('img'),
            projectId: Value('p1'),
            position: Value(0),
            kind: Value('image'),
            volume: Value(1),
            muted: Value(false),
          ),
        );
    await database.into(database.editorClips).insert(
          const EditorClipsCompanion(
            id: Value('i1'),
            layerId: Value('img'),
            sortKey: Value(0),
            sourceUri: Value('/media/photo.jpg'),
            startMs: Value(0),
            durationMs: Value(3000),
            inPointMs: Value(0),
            outPointMs: Value(3000),
            reversed: Value(false),
            volume: Value(1),
            filterId: Value('sepia'),
            adjustmentsJson: Value('{}'),
          ),
        );
    engine = FakeMediaEngine(media: {});
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        mediaEngineProvider.overrideWithValue(engine),
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

  test('swaps the photo for its cutout and undo brings it back', () async {
    final ok = await controller().removeBackground('i1');

    expect(ok, isTrue);
    final (input, output) = engine.cutouts.single;
    expect(input, '/media/photo.jpg');
    expect(output.startsWith(root.path), isTrue);
    expect(output.endsWith('.png'), isTrue);
    final clip = container
        .read(editorControllerProvider)
        .requireValue
        .project
        .clipById('i1')!;
    expect(clip.sourceUri, output);
    expect((clip.sourceWidth, clip.sourceHeight), (640, 480));
    expect(clip.filterId, 'sepia');

    controller().undo();
    await Future<void>.delayed(Duration.zero);
    expect(
      container
          .read(editorControllerProvider)
          .requireValue
          .project
          .clipById('i1')!
          .sourceUri,
      '/media/photo.jpg',
    );
  });

  test('an engine failure changes nothing', () async {
    engine.failCutout = true;

    final ok = await controller().removeBackground('i1');

    expect(ok, isFalse);
    expect(
      container
          .read(editorControllerProvider)
          .requireValue
          .project
          .clipById('i1')!
          .sourceUri,
      '/media/photo.jpg',
    );
  });

  test('an unknown clip is refused without calling the engine', () async {
    final ok = await controller().removeBackground('missing');

    expect(ok, isFalse);
    expect(engine.cutouts, isEmpty);
  });
}
