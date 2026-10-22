import 'package:cutter/features/editor/domain/clip_placement.dart';
import 'package:cutter/features/editor/domain/clip_timing_use_cases.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_editor_ports.dart';

Project _unwrap(EditorResult<Project> result) {
  return switch (result) {
    Ok<Project>(:final value) => value,
    Err<Project>(:final failure) => throw StateError('expected Ok: $failure'),
  };
}

EditorFailure _failureOf(EditorResult<Project> result) {
  return switch (result) {
    Ok<Project>() => throw StateError('expected Err'),
    Err<Project>(:final failure) => failure,
  };
}

void main() {
  late InMemoryProjectRepository repository;
  late Project original;

  setUp(() {
    original = buildFixtureProject();
    repository = InMemoryProjectRepository([original]);
  });

  void expectUntouched() {
    expect(repository.saveCount, 0);
    expect(repository.projects['p1'], original);
  }

  group('TrimClip', () {
    late TrimClip trim;

    setUp(() => trim = TrimClip(repository));

    test('shortens_the_out_point_and_saves', () async {
      final result = await trim(
        projectId: 'p1',
        clipId: 'c1',
        inPointMs: 0,
        outPointMs: 3000,
      );

      final clip = _unwrap(result).clipById('c1')!;
      expect(clip.durationMs, 3000);
      expect(clip.startMs, 0);
      expect(repository.saveCount, 1);
      expect(repository.projects['p1']!.clipById('c1')!.durationMs, 3000);
    });

    test('moving_the_in_point_keeps_remaining_frames_in_place', () async {
      final result = await trim(
        projectId: 'p1',
        clipId: 'c1',
        inPointMs: 1000,
        outPointMs: 4000,
      );

      final clip = _unwrap(result).clipById('c1')!;
      expect(clip.inPointMs, 1000);
      expect(clip.startMs, 1000);
      expect(clip.durationMs, 3000);
    });

    test('allows_extending_up_to_a_touching_neighbour', () async {
      final result = await trim(
        projectId: 'p1',
        clipId: 'c1',
        inPointMs: 0,
        outPointMs: 6000,
      );

      expect(_unwrap(result).clipById('c1')!.durationMs, 6000);
    });

    test('rejects_trim_that_overlaps_a_neighbour', () async {
      final result = await trim(
        projectId: 'p1',
        clipId: 'c1',
        inPointMs: 0,
        outPointMs: 7000,
      );

      expect(_failureOf(result), const Overlap('c2'));
      expectUntouched();
    });

    test('rejects_duration_below_the_minimum', () async {
      final result = await trim(
        projectId: 'p1',
        clipId: 'c1',
        inPointMs: 1000,
        outPointMs: 1020,
      );

      expect(_failureOf(result), const ZeroDuration());
      expectUntouched();
    });

    test('rejects_negative_duration', () async {
      final result = await trim(
        projectId: 'p1',
        clipId: 'c1',
        inPointMs: 2000,
        outPointMs: 1000,
      );

      expect(_failureOf(result), const ZeroDuration());
      expectUntouched();
    });

    test('rejects_out_point_beyond_the_source', () async {
      final result = await trim(
        projectId: 'p1',
        clipId: 'c1',
        inPointMs: 0,
        outPointMs: 11000,
      );

      expect(_failureOf(result), const TrimOutOfSource());
      expectUntouched();
    });

    test('rejects_in_point_before_the_source_start', () async {
      final result = await trim(
        projectId: 'p1',
        clipId: 'c1',
        inPointMs: -100,
        outPointMs: 3000,
      );

      expect(_failureOf(result), const TrimOutOfSource());
      expectUntouched();
    });

    test('reports_unknown_project_and_clip', () async {
      final noProject = await trim(
        projectId: 'nope',
        clipId: 'c1',
        inPointMs: 0,
        outPointMs: 1000,
      );
      final noClip = await trim(
        projectId: 'p1',
        clipId: 'nope',
        inPointMs: 0,
        outPointMs: 1000,
      );

      expect(_failureOf(noProject), const ProjectNotFound('nope'));
      expect(_failureOf(noClip), const ClipNotFound('nope'));
      expectUntouched();
    });
  });

  group('SplitClip', () {
    late SplitClip split;

    setUp(() => split = SplitClip(repository, SequentialIdGenerator()));

    test('produces_two_adjacent_clips_preserving_total_duration', () async {
      final result = await split(projectId: 'p1', clipId: 'c1', atMs: 1500);

      final project = _unwrap(result);
      final first = project.clipById('c1')!;
      final second = project.clipById('id-1')!;
      expect(first.startMs, 0);
      expect(first.range.endMs, 1500);
      expect(second.startMs, 1500);
      expect(second.inPointMs, 1500);
      expect(second.outPointMs, 4000);
      expect(first.durationMs + second.durationMs, 4000);
      expect(repository.saveCount, 1);
    });

    test('keeps_clips_of_the_layer_sorted', () async {
      final result = await split(projectId: 'p1', clipId: 'c1', atMs: 1500);

      final ids = _unwrap(result).layerById('v1')!.clips.map((c) => c.id);
      expect(ids, ['c1', 'id-1', 'c2']);
    });

    test('splits_a_reversed_clip_on_the_matching_source_side', () async {
      final reversed = original.replaceLayer(
        original.layerById('v1')!.withClips([
          original.clipById('c1')!.copyWith(reversed: true),
          original.clipById('c2')!,
        ]),
      );
      repository = InMemoryProjectRepository([reversed]);
      split = SplitClip(repository, SequentialIdGenerator());

      final result = await split(projectId: 'p1', clipId: 'c1', atMs: 1000);

      final project = _unwrap(result);
      final first = project.clipById('c1')!;
      final second = project.clipById('id-1')!;
      expect(first.inPointMs, 3000);
      expect(first.outPointMs, 4000);
      expect(second.inPointMs, 0);
      expect(second.outPointMs, 3000);
      expect(second.startMs, 1000);
    });

    test('rejects_playhead_at_or_outside_the_clip_bounds', () async {
      for (final at in [0, 4000, 5000, -10]) {
        final result = await split(projectId: 'p1', clipId: 'c1', atMs: at);
        expect(_failureOf(result), const PlayheadOutsideClip());
      }
      expectUntouched();
    });

    test('reports_unknown_clip', () async {
      final result = await split(projectId: 'p1', clipId: 'nope', atMs: 100);

      expect(_failureOf(result), const ClipNotFound('nope'));
      expectUntouched();
    });
  });

  group('MoveClip', () {
    late MoveClip move;

    setUp(() => move = MoveClip(repository));

    test('moves_a_clip_in_time_to_a_free_slot', () async {
      final result = await move(
        projectId: 'p1',
        clipId: 'c2',
        targetLayerId: 'v1',
        startMs: 4000,
      );

      final project = _unwrap(result);
      expect(project.clipById('c2')!.startMs, 4000);
      expect(project.layerById('v1')!.clips.length, 2);
      expect(repository.saveCount, 1);
    });

    test('moves_a_clip_to_another_layer_of_the_same_kind', () async {
      final withSecondVideoLayer = original.withLayers([
        ...original.layers,
        Layer(id: 'v2', name: 'Video 2', kind: MediaKind.video),
      ]);
      repository = InMemoryProjectRepository([withSecondVideoLayer]);
      move = MoveClip(repository);

      final result = await move(
        projectId: 'p1',
        clipId: 'c2',
        targetLayerId: 'v2',
        startMs: 500,
      );

      final project = _unwrap(result);
      expect(project.layerOfClip('c2')!.id, 'v2');
      expect(project.clipById('c2')!.layerId, 'v2');
      expect(project.clipById('c2')!.startMs, 500);
      expect(project.layerById('v1')!.clips.map((c) => c.id), ['c1']);
    });

    test('rejects_a_layer_of_the_wrong_kind', () async {
      final result = await move(
        projectId: 'p1',
        clipId: 'c2',
        targetLayerId: 'a1',
        startMs: 0,
      );

      expect(_failureOf(result), const WrongLayerKind());
      expectUntouched();
    });

    test('rejects_overlap_without_deleting_either_clip', () async {
      final result = await move(
        projectId: 'p1',
        clipId: 'c2',
        targetLayerId: 'v1',
        startMs: 3000,
      );

      expect(_failureOf(result), const Overlap('c1'));
      expectUntouched();
      expect(repository.projects['p1']!.layerById('v1')!.clips.length, 2);
    });

    test('rejects_a_negative_start', () async {
      final result = await move(
        projectId: 'p1',
        clipId: 'c2',
        targetLayerId: 'v1',
        startMs: -1,
      );

      expect(_failureOf(result), const NegativeStart());
      expectUntouched();
    });

    test('reports_unknown_clip_and_layer', () async {
      final noClip = await move(
        projectId: 'p1',
        clipId: 'nope',
        targetLayerId: 'v1',
        startMs: 0,
      );
      final noLayer = await move(
        projectId: 'p1',
        clipId: 'c1',
        targetLayerId: 'nope',
        startMs: 0,
      );

      expect(_failureOf(noClip), const ClipNotFound('nope'));
      expect(_failureOf(noLayer), const LayerNotFound('nope'));
      expectUntouched();
    });
  });

  group('ArrangeClip', () {
    late ArrangeClip arrange;

    setUp(() => arrange = ArrangeClip(repository));

    test('close gap before moves the clip against the one before', () async {
      final project = _unwrap(
        await arrange(
          projectId: 'p1',
          clipId: 'c2',
          arrangement: ClipArrangement.closeGapBefore,
        ),
      );

      expect(project.clipById('c2')!.startMs, 4000);
      expect(repository.saveCount, 1);
    });

    test('close gap after moves the clip against the one after', () async {
      final project = _unwrap(
        await arrange(
          projectId: 'p1',
          clipId: 'c1',
          arrangement: ClipArrangement.closeGapAfter,
        ),
      );

      expect(project.clipById('c1')!.startMs, 2000);
    });

    test('to end puts the clip after the last one on its layer', () async {
      final project = _unwrap(
        await arrange(
          projectId: 'p1',
          clipId: 'c1',
          arrangement: ClipArrangement.toEnd,
        ),
      );

      expect(project.clipById('c1')!.startMs, 8000);
    });

    test('does not save when the clip is already there', () async {
      final result = await arrange(
        projectId: 'p1',
        clipId: 'c1',
        arrangement: ClipArrangement.toStart,
      );

      expect(_unwrap(result), original);
      expectUntouched();
    });

    test('reports a clip that does not exist', () async {
      final result = await arrange(
        projectId: 'p1',
        clipId: 'nope',
        arrangement: ClipArrangement.toStart,
      );

      expect(_failureOf(result), isA<ClipNotFound>());
    });
  });
}
