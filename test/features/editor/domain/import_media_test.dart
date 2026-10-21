import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/import_media.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_editor_ports.dart';

MediaAsset _asset(
  String id,
  MediaKind kind, {
  int durationMs = 3000,
  bool supported = true,
}) =>
    MediaAsset(
      id: id,
      uri: '/media/$id',
      kind: kind,
      durationMs: durationMs,
      supported: supported,
    );

Project _ok(EditorResult<Project> result) {
  expect(result, isA<Ok<Project>>());
  return (result as Ok<Project>).value;
}

void main() {
  late InMemoryProjectRepository repository;
  late ImportMedia importMedia;

  setUp(() {
    repository = InMemoryProjectRepository([
      Project(id: 'empty', name: 'Empty'),
      buildFixtureProject(),
    ]);
    importMedia = ImportMedia(repository, SequentialIdGenerator());
  });

  test('the first video of an empty project starts a main layer at zero',
      () async {
    final project = _ok(
      await importMedia(
        projectId: 'empty',
        assets: [_asset('v', MediaKind.video, durationMs: 5000)],
        atMs: 1200,
      ),
    );

    expect(project.layers, hasLength(1));
    final layer = project.layers.single;
    expect(layer.kind, MediaKind.video);
    final clip = layer.clips.single;
    expect((clip.startMs, clip.inPointMs, clip.outPointMs), (0, 0, 5000));
    expect(clip.sourceUri, '/media/v');
    expect(repository.saveCount, 1);
  });

  test('appended visuals play one after another at the end of the sequence',
      () async {
    final project = _ok(
      await importMedia(
        projectId: 'p1',
        assets: [
          _asset('v', MediaKind.video, durationMs: 1000),
          _asset('i', MediaKind.image),
          _asset('w', MediaKind.video, durationMs: 500),
        ],
        atMs: 0,
      ),
    );

    // The fixture's video layer ends at 8000.
    final video = project.layerById('v1')!;
    expect(
      video.clips.map((c) => (c.assetId, c.startMs)).toList().sublist(2),
      [('v', 8000), ('w', 12000)],
    );
    final image = project.layers.firstWhere((l) => l.kind == MediaKind.image);
    expect(image.clips.single.startMs, 9000);
    expect(image.clips.single.durationMs, 3000);
  });

  test('an image can later be stretched beyond its first duration', () async {
    final project = _ok(
      await importMedia(
        projectId: 'empty',
        assets: [_asset('i', MediaKind.image)],
        atMs: 0,
      ),
    );

    final clip = project.layers.single.clips.single;
    expect(clip.sourceDurationMs, greaterThan(clip.durationMs));
  });

  test('sound goes to the playhead on the first audio layer with room',
      () async {
    final project = _ok(
      await importMedia(
        projectId: 'p1',
        assets: [_asset('song', MediaKind.audio, durationMs: 2000)],
        atMs: 9000,
      ),
    );

    final audio = project.layers.where((l) => l.kind == MediaKind.audio);
    expect(audio, hasLength(1));
    expect(
      audio.single.clips.map((c) => c.startMs),
      containsAll([0, 9000]),
    );
  });

  test('sound that would overlap gets a new audio layer behind the others',
      () async {
    final project = _ok(
      await importMedia(
        projectId: 'p1',
        assets: [_asset('song', MediaKind.audio, durationMs: 2000)],
        atMs: 0,
      ),
    );

    final audio =
        project.layers.where((l) => l.kind == MediaKind.audio).toList();
    expect(audio, hasLength(2));
    expect(project.layers.last, audio.last);
    expect(audio.last.clips.single.startMs, 0);
  });

  test('an overlay goes on a new front layer at the playhead', () async {
    final project = _ok(
      await importMedia(
        projectId: 'p1',
        assets: [
          _asset('a', MediaKind.video, durationMs: 1000),
          _asset('b', MediaKind.video, durationMs: 1000),
        ],
        atMs: 2500,
        placement: ImportPlacement.overlay,
      ),
    );

    final front = project.layers.first;
    expect(front.id, isNot('v1'));
    expect(front.clips.map((c) => c.startMs), [2500, 3500]);
  });

  test('rejects the whole import when a file is unsupported', () async {
    final result = await importMedia(
      projectId: 'p1',
      assets: [
        _asset('ok', MediaKind.video),
        _asset('bad', MediaKind.video, supported: false),
      ],
      atMs: 0,
    );

    expect(result, isA<Err<Project>>());
    expect((result as Err<Project>).failure, isA<UnsupportedMedia>());
    expect(repository.saveCount, 0);
  });

  test('fails on an unknown project', () async {
    final result = await importMedia(
      projectId: 'nope',
      assets: [_asset('v', MediaKind.video)],
      atMs: 0,
    );

    expect((result as Err<Project>).failure, isA<ProjectNotFound>());
  });

  test('keeps existing layers untouched', () async {
    final before = repository.projects['p1']!;
    final project = _ok(
      await importMedia(
        projectId: 'p1',
        assets: [_asset('v', MediaKind.video)],
        atMs: 0,
      ),
    );

    final audio = project.layerById('a1')!;
    expect(audio, before.layerById('a1'));
  });
}
