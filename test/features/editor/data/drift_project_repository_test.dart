import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/features/editor/data/drift_project_repository.dart';
import 'package:cutter/features/editor/data/editor_dao.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
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

  test('an unknown id loads as null', () async {
    expect(await repository.find('missing'), isNull);
  });

  test('firstProjectId is null when empty and the oldest otherwise', () async {
    expect(await repository.firstProjectId(), isNull);

    await _storeEmptyProject(dao, id: 'newer', createdAtMs: 500);
    await _storeEmptyProject(dao, id: 'older', createdAtMs: 100);

    expect(await repository.firstProjectId(), 'older');
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
}
