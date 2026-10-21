import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/features/editor/data/drift_project_repository.dart';
import 'package:cutter/features/editor/data/drift_version_repository.dart';
import 'package:cutter/features/editor/data/editor_dao.dart';
import 'package:cutter/features/editor/domain/canvas.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/clip_transform.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/domain/project_version.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

Clip _clip(
  String id, {
  required String layerId,
  MediaKind kind = MediaKind.video,
  int startMs = 0,
  int durationMs = 1000,
  bool reversed = false,
  double volume = 1,
  String? filterId,
  Map<String, double> adjustments = const {},
}) {
  final sourceUri = 'file:///media/$id.mp4';
  return Clip(
    id: id,
    layerId: layerId,
    assetId: sourceUri,
    kind: kind,
    sourceUri: sourceUri,
    sourceDurationMs: durationMs,
    startMs: startMs,
    inPointMs: 0,
    outPointMs: durationMs,
    reversed: reversed,
    volume: volume,
    filterId: filterId,
    adjustments: adjustments,
  );
}

Project _project({
  required List<Layer> layers,
  String id = 'project-1',
}) {
  return Project(
    id: id,
    name: 'My project',
    layers: layers,
  );
}

Future<void> _storeEmptyProject(
  EditorDao dao, {
  required String id,
  required int createdAtMs,
}) {
  return dao.replaceProject(
    ProjectRows(
      project: EditorProject(
        id: id,
        name: 'My project',
        createdAtMs: createdAtMs,
        updatedAtMs: createdAtMs,
        canvasWidth: 1080,
        canvasHeight: 1920,
        fps: 30,
      ),
      layers: const [],
      clips: const [],
    ),
  );
}

void main() {
  late AppDatabase database;
  late EditorDao dao;
  late DriftProjectRepository repository;

  setUp(() {
    database = AppDatabase.inMemory();
    dao = EditorDao(database);
    repository = DriftProjectRepository(dao);
  });

  tearDown(() async {
    await database.close();
  });

  test('a saved project loads equal, with clips sorted by start', () async {
    final project = _project(
      layers: [
        Layer(
          id: 'layer-video',
          name: '',
          kind: MediaKind.video,
          volume: 0.8,
          clips: [
            _clip(
              'clip-b',
              layerId: 'layer-video',
              startMs: 2000,
              reversed: true,
              volume: 0.25,
              filterId: 'sepia',
              adjustments: {'brightness': 0.5, 'contrast': -0.25},
            ),
            _clip('clip-a', layerId: 'layer-video'),
          ],
        ),
        Layer(
          id: 'layer-audio',
          name: '',
          kind: MediaKind.audio,
          volume: 0.5,
          muted: true,
          clips: [
            _clip(
              'clip-c',
              layerId: 'layer-audio',
              kind: MediaKind.audio,
              durationMs: 3000,
            ),
          ],
        ),
      ],
    );

    await repository.save(project);
    final loaded = await repository.find('project-1');

    expect(loaded, isNotNull);
    expect(loaded!.layers.map((layer) => layer.id), [
      'layer-video',
      'layer-audio',
    ]);
    expect(loaded.layers.first.clips.map((clip) => clip.id), [
      'clip-a',
      'clip-b',
    ]);
    final restored = loaded.layers.first.clips.last;
    expect(restored.reversed, isTrue);
    expect(restored.volume, 0.25);
    expect(restored.filterId, 'sepia');
    expect(restored.adjustments, {'brightness': 0.5, 'contrast': -0.25});
    expect(loaded.layers.last.muted, isTrue);
    expect(loaded.layers.last.kind, MediaKind.audio);

    await repository.save(loaded);
    expect(await repository.find('project-1'), loaded);
  });

  test('saving again replaces the previous layers and clips', () async {
    final first = _project(
      layers: [
        Layer(
          id: 'layer-1',
          name: '',
          kind: MediaKind.video,
          clips: [
            _clip('clip-1', layerId: 'layer-1'),
            _clip('clip-2', layerId: 'layer-1', startMs: 1000),
          ],
        ),
      ],
    );
    final second = _project(
      layers: [
        Layer(
          id: 'layer-1',
          name: '',
          kind: MediaKind.video,
          clips: [_clip('clip-1', layerId: 'layer-1', durationMs: 500)],
        ),
      ],
    );

    await repository.save(first);
    await repository.save(second);

    final loaded = await repository.find('project-1');
    expect(loaded!.layers.single.clips.map((clip) => clip.id), ['clip-1']);
    expect(loaded.layers.single.clips.single.durationMs, 500);
  });

  test('deleting a project removes its rows and keeps exported videos',
      () async {
    await repository.save(
      _project(
        layers: [
          Layer(
            id: 'layer-1',
            name: '',
            kind: MediaKind.video,
            clips: [_clip('clip-1', layerId: 'layer-1')],
          ),
        ],
      ),
    );
    await database.into(database.editorExports).insert(
          EditorExportsCompanion.insert(
            id: 'e1',
            projectId: const Value('project-1'),
            projectName: 'Trip',
            path: '/videos/trip.mp4',
            width: 1080,
            height: 1920,
            fps: 30,
            durationMs: 1000,
            sizeBytes: 1,
            createdAtMs: 1,
            preset: 'project/standard',
          ),
        );

    await repository.delete('project-1');
    await repository.delete('missing');

    expect(await repository.find('project-1'), isNull);
    expect(await database.select(database.editorLayers).get(), isEmpty);
    expect(await database.select(database.editorClips).get(), isEmpty);
    final exports = await database.select(database.editorExports).get();
    expect(exports.single.projectId, isNull);
  });

  test('an unknown id loads as null', () async {
    expect(await repository.find('missing'), isNull);
  });

  test('summaries count layers, clips and duration, newest first', () async {
    expect(await repository.summaries(), isEmpty);

    await repository.save(
      _project(
        layers: [
          Layer(
            id: 'layer-1',
            name: '',
            kind: MediaKind.video,
            clips: [
              _clip('clip-1', layerId: 'layer-1'),
              _clip('clip-2', layerId: 'layer-1', startMs: 3000),
            ],
          ),
          Layer(id: 'layer-2', name: '', kind: MediaKind.audio),
        ],
      ),
    );
    await _storeEmptyProject(dao, id: 'newer', createdAtMs: 500);

    final summaries = await repository.summaries();

    expect(summaries.map((summary) => summary.id), ['project-1', 'newer']);
    final stored = summaries.first;
    expect(stored.layerCount, 2);
    expect(stored.clipCount, 2);
    expect(stored.durationMs, 4000);
    // The cover is the first video clip, not the audio layer.
    expect(stored.coverUri, 'file:///media/clip-1.mp4');
    expect(stored.coverMs, 0);
    expect(summaries.last.layerCount, 0);
    expect(summaries.last.durationMs, 0);
    expect(summaries.last.coverUri, isNull);
  });

  test('a trimmed clip keeps the duration of its source', () async {
    final project = _project(
      layers: [
        Layer(
          id: 'layer-1',
          name: '',
          kind: MediaKind.video,
          clips: [
            const Clip(
              id: 'clip-1',
              layerId: 'layer-1',
              assetId: 'file:///media/clip-1.mp4',
              sourceUri: 'file:///media/clip-1.mp4',
              kind: MediaKind.video,
              // The source lasts ten seconds and the clip plays the part
              // between one and three seconds of it.
              sourceDurationMs: 10000,
              startMs: 0,
              inPointMs: 1000,
              outPointMs: 3000,
            ),
          ],
        ),
      ],
    );

    await repository.save(project);
    final loaded = await repository.find('project-1');

    final clip = loaded!.layers.single.clips.single;
    expect(clip.sourceDurationMs, 10000);
    expect(clip.inPointMs, 1000);
    expect(clip.outPointMs, 3000);
    expect(clip.durationMs, 2000);
  });

  test('a failing save leaves the previous rows intact', () async {
    final original = _project(
      layers: [
        Layer(
          id: 'layer-1',
          name: '',
          kind: MediaKind.video,
          clips: [_clip('clip-1', layerId: 'layer-1')],
        ),
      ],
    );
    await repository.save(original);

    final broken = _project(
      layers: [
        Layer(
          id: 'layer-1',
          name: '',
          kind: MediaKind.video,
          clips: [
            _clip('duplicate', layerId: 'layer-1'),
            _clip('duplicate', layerId: 'layer-1', startMs: 1000),
          ],
        ),
      ],
    );

    await expectLater(repository.save(broken), throwsA(anything));

    expect(await repository.find('project-1'), original);
  });

  test('the canvas and the clip transforms survive a round trip', () async {
    const transform = ClipTransform(
      x: 0.2,
      y: -0.3,
      scale: 1.75,
      rotation: 45,
      opacity: 0.5,
      flipX: true,
      fit: ClipFit.fill,
    );
    final project = _project(
      layers: [
        Layer(
          id: 'l1',
          name: '',
          kind: MediaKind.video,
          clips: [
            _clip('c1', layerId: 'l1').copyWith(transform: transform),
          ],
        ),
      ],
    ).withCanvas(CanvasPreset.square.canvas(fps: 60));

    await repository.save(project);
    final loaded = await repository.find(project.id);

    expect(loaded!.canvas, const Canvas(width: 1080, height: 1080, fps: 60));
    expect(loaded.clipById('c1')!.transform, transform);
  });

  test('a saved version keeps a snapshot and marks the project saved',
      () async {
    final versions = DriftVersionRepository(database);
    final project = _project(
      layers: [
        Layer(
          id: 'l1',
          name: '',
          kind: MediaKind.video,
          clips: [
            _clip('c1', layerId: 'l1')
                .copyWith(transform: const ClipTransform(scale: 2)),
          ],
        ),
      ],
    );
    await repository.save(project);
    expect((await repository.summaries()).single.savedAtMs, isNull);

    final savedAt = DateTime.now().millisecondsSinceEpoch + 1000;
    final version = ProjectVersion(
      id: 'v1',
      projectId: project.id,
      name: 'Cut 1',
      createdAtMs: savedAt,
      durationMs: project.durationMs,
    );
    await versions.save(version, project);

    expect(await versions.versionsOf(project.id), [version]);
    expect(await versions.snapshotOf('v1'), project);
    expect((await repository.summaries()).single.savedAtMs, savedAt);

    // Deleting the project's rows on the next save keeps its versions.
    await repository.save(project.withLayers([]));
    expect(await versions.snapshotOf('v1'), project);
  });
}
