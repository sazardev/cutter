import 'package:cutter/features/editor/domain/clip_edit_use_cases.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_editor_ports.dart';

Project _ok(EditorResult<Project> result) {
  expect(result, isA<Ok<Project>>());
  return (result as Ok<Project>).value;
}

EditorFailure _failure(EditorResult<Project> result) {
  expect(result, isA<Err<Project>>());
  return (result as Err<Project>).failure;
}

void main() {
  late InMemoryProjectRepository repository;

  setUp(() {
    repository = InMemoryProjectRepository([buildFixtureProject()]);
  });

  group('DeleteClip', () {
    test('removes the clip and leaves the gap', () async {
      final project = _ok(
        await DeleteClip(repository)(projectId: 'p1', clipId: 'c1'),
      );

      final clips = project.layerById('v1')!.clips;
      expect(clips.map((c) => (c.id, c.startMs)), [('c2', 6000)]);
      expect(repository.saveCount, 1);
    });

    test('with ripple, later clips on the layer close the gap', () async {
      final project = _ok(
        await DeleteClip(repository)(
          projectId: 'p1',
          clipId: 'c1',
          ripple: true,
        ),
      );

      expect(
        project.layerById('v1')!.clips.map((c) => (c.id, c.startMs)),
        [('c2', 2000)],
      );
      // Other layers do not move.
      expect(project.layerById('a1')!.clips.single.startMs, 0);
    });

    test('fails on an unknown clip and saves nothing', () async {
      final failure = _failure(
        await DeleteClip(repository)(projectId: 'p1', clipId: 'zz'),
      );

      expect(failure, isA<ClipNotFound>());
      expect(repository.saveCount, 0);
    });
  });

  group('DuplicateClip', () {
    test('places the copy right after the original and shifts what follows',
        () async {
      final project = _ok(
        await DuplicateClip(repository, SequentialIdGenerator())(
          projectId: 'p1',
          clipId: 'c1',
        ),
      );

      final clips = project.layerById('v1')!.clips;
      expect(
        clips.map((c) => (c.id, c.startMs, c.durationMs)),
        [('c1', 0, 4000), ('id-1', 4000, 4000), ('c2', 10000, 2000)],
      );
      expect(clips[1].sourceUri, clips[0].sourceUri);
    });
  });

  group('SetLayerMuted', () {
    test('mutes and unmutes a layer', () async {
      final muted = _ok(
        await SetLayerMuted(repository)(
          projectId: 'p1',
          layerId: 'a1',
          muted: true,
        ),
      );
      expect(muted.layerById('a1')!.muted, isTrue);

      final unmuted = _ok(
        await SetLayerMuted(repository)(
          projectId: 'p1',
          layerId: 'a1',
          muted: false,
        ),
      );
      expect(unmuted.layerById('a1')!.muted, isFalse);
    });
  });

  group('DeleteLayer', () {
    test('removes the layer with its clips', () async {
      final project = _ok(
        await DeleteLayer(repository)(projectId: 'p1', layerId: 'a1'),
      );

      expect(project.layerById('a1'), isNull);
      expect(project.layers, hasLength(1));
    });

    test('fails on an unknown layer', () async {
      final failure = _failure(
        await DeleteLayer(repository)(projectId: 'p1', layerId: 'zz'),
      );

      expect(failure, isA<LayerNotFound>());
    });
  });

  group('RestoreProject', () {
    test('stores the given snapshot as it is', () async {
      final snapshot = buildFixtureProject().withLayers([]);
      final project = _ok(await RestoreProject(repository)(snapshot));

      expect(project, snapshot);
      expect(repository.projects['p1'], snapshot);
    });
  });
}
