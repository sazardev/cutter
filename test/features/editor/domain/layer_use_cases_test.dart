import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/layer_use_cases.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_editor_ports.dart';

MediaAsset _asset({
  String id = 'asset-new',
  MediaKind kind = MediaKind.video,
  int durationMs = 3000,
  bool supported = true,
}) =>
    MediaAsset(
      id: id,
      uri: 'file:///$id',
      kind: kind,
      durationMs: durationMs,
      supported: supported,
    );

Project _okProject(EditorResult<Project> result) {
  expect(result, isA<Ok<Project>>());
  return (result as Ok<Project>).value;
}

EditorFailure _failure(EditorResult<Project> result) {
  expect(result, isA<Err<Project>>());
  return (result as Err<Project>).failure;
}

void main() {
  group('AddClipToLayer', () {
    late InMemoryProjectRepository repository;
    late AddClipToLayer addClip;

    setUp(() {
      repository = InMemoryProjectRepository([buildFixtureProject()]);
      addClip = AddClipToLayer(repository, SequentialIdGenerator());
    });

    test('creates_clip_with_intrinsic_duration', () async {
      final result = await addClip(
        projectId: 'p1',
        layerId: 'v1',
        asset: _asset(),
        startMs: 4000,
      );

      final project = _okProject(result);
      final clip = project.layerById('v1')!.clips.firstWhere(
            (c) => c.id == 'id-1',
          );
      expect(clip.startMs, 4000);
      expect(clip.inPointMs, 0);
      expect(clip.outPointMs, 3000);
      expect(clip.durationMs, 3000);
      expect(clip.sourceDurationMs, 3000);
      expect(clip.assetId, 'asset-new');
      expect(clip.kind, MediaKind.video);
      expect(clip.layerId, 'v1');
      expect(repository.projects['p1'], project);
      expect(repository.saveCount, 1);
    });

    test('keeps_clips_sorted_by_start', () async {
      final result = await addClip(
        projectId: 'p1',
        layerId: 'v1',
        asset: _asset(durationMs: 1000),
        startMs: 4500,
      );

      final starts =
          _okProject(result).layerById('v1')!.clips.map((c) => c.startMs);
      expect(starts, [0, 4500, 6000]);
    });

    test('imports_audio_into_audio_layer', () async {
      final result = await addClip(
        projectId: 'p1',
        layerId: 'a1',
        asset: _asset(kind: MediaKind.audio, durationMs: 2000),
        startMs: 8000,
      );

      final clip = _okProject(result).layerById('a1')!.clips.last;
      expect(clip.kind, MediaKind.audio);
      expect(clip.startMs, 8000);
    });

    test('rejects_unsupported_media_and_saves_nothing', () async {
      final result = await addClip(
        projectId: 'p1',
        layerId: 'v1',
        asset: _asset(supported: false),
        startMs: 4000,
      );

      expect(_failure(result), const UnsupportedMedia());
      expect(repository.saveCount, 0);
    });

    test('rejects_wrong_layer_kind', () async {
      final result = await addClip(
        projectId: 'p1',
        layerId: 'a1',
        asset: _asset(),
        startMs: 9000,
      );

      expect(_failure(result), const WrongLayerKind());
      expect(repository.saveCount, 0);
    });

    test('rejects_negative_start', () async {
      final result = await addClip(
        projectId: 'p1',
        layerId: 'v1',
        asset: _asset(),
        startMs: -1,
      );

      expect(_failure(result), const NegativeStart());
      expect(repository.saveCount, 0);
    });

    test('rejects_overlap_with_existing_clip', () async {
      final result = await addClip(
        projectId: 'p1',
        layerId: 'v1',
        asset: _asset(),
        startMs: 3000,
      );

      expect(_failure(result), const Overlap('c1'));
      expect(repository.projects['p1'], buildFixtureProject());
      expect(repository.saveCount, 0);
    });

    test('rejects_asset_shorter_than_minimum', () async {
      final result = await addClip(
        projectId: 'p1',
        layerId: 'v1',
        asset: _asset(durationMs: minClipDurationMs - 1),
        startMs: 4000,
      );

      expect(_failure(result), const ZeroDuration());
      expect(repository.saveCount, 0);
    });

    test('reports_unknown_project_and_layer', () async {
      final missingProject = await addClip(
        projectId: 'nope',
        layerId: 'v1',
        asset: _asset(),
        startMs: 0,
      );
      final missingLayer = await addClip(
        projectId: 'p1',
        layerId: 'nope',
        asset: _asset(),
        startMs: 0,
      );

      expect(_failure(missingProject), const ProjectNotFound('nope'));
      expect(_failure(missingLayer), const LayerNotFound('nope'));
      expect(repository.saveCount, 0);
    });
  });

  group('ReorderLayers', () {
    late InMemoryProjectRepository repository;
    late ReorderLayers reorder;

    setUp(() {
      repository = InMemoryProjectRepository([buildFixtureProject()]);
      reorder = ReorderLayers(repository);
    });

    test('applies_new_order_with_front_layer_first', () async {
      final result = await reorder(projectId: 'p1', layerIds: ['a1', 'v1']);

      final project = _okProject(result);
      expect(project.layers.map((l) => l.id), ['a1', 'v1']);
      expect(repository.projects['p1']!.layers.first.id, 'a1');
      expect(repository.saveCount, 1);
    });

    test('keeps_clips_of_each_layer', () async {
      final result = await reorder(projectId: 'p1', layerIds: ['a1', 'v1']);

      final project = _okProject(result);
      expect(project.layerById('v1')!.clips.map((c) => c.id), ['c1', 'c2']);
      expect(project.layerById('a1')!.clips.map((c) => c.id), ['m1']);
    });

    test('rejects_missing_layer', () async {
      final result = await reorder(projectId: 'p1', layerIds: ['v1']);

      expect(_failure(result), const InvalidLayerOrder());
      expect(repository.saveCount, 0);
    });

    test('rejects_duplicate_layer', () async {
      final result = await reorder(projectId: 'p1', layerIds: ['v1', 'v1']);

      expect(_failure(result), const InvalidLayerOrder());
      expect(repository.saveCount, 0);
    });

    test('rejects_unknown_layer', () async {
      final result = await reorder(projectId: 'p1', layerIds: ['v1', 'zz']);

      expect(_failure(result), const InvalidLayerOrder());
      expect(repository.projects['p1'], buildFixtureProject());
    });

    test('reports_unknown_project', () async {
      final result = await reorder(projectId: 'nope', layerIds: ['v1', 'a1']);

      expect(_failure(result), const ProjectNotFound('nope'));
    });
  });

  group('SetLayerVolume', () {
    late InMemoryProjectRepository repository;
    late SetLayerVolume setVolume;

    setUp(() {
      repository = InMemoryProjectRepository([buildFixtureProject()]);
      setVolume = SetLayerVolume(repository);
    });

    test('sets_volume_and_mute', () async {
      final result = await setVolume(
        projectId: 'p1',
        layerId: 'a1',
        volume: 0.5,
        muted: true,
      );

      final layer = _okProject(result).layerById('a1')!;
      expect(layer.volume, 0.5);
      expect(layer.muted, isTrue);
    });

    test('rejects_volume_out_of_range', () async {
      final result = await setVolume(
        projectId: 'p1',
        layerId: 'a1',
        volume: 1.5,
        muted: false,
      );

      expect(_failure(result), const InvalidVolume());
      expect(repository.saveCount, 0);
    });
  });
}
