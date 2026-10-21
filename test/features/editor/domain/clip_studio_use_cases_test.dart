import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/clip_crop.dart';
import 'package:cutter/features/editor/domain/clip_studio_use_cases.dart';
import 'package:cutter/features/editor/domain/clip_timing_use_cases.dart';
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
  late InMemoryProjectRepository projects;

  setUp(() => projects = InMemoryProjectRepository([buildFixtureProject()]));

  group('speed', () {
    test('double speed halves the clip on the timeline', () async {
      final project = _ok(
        await SetClipSpeed(projects)(
          projectId: 'p1',
          clipId: 'c1',
          speed: 2,
        ),
      );

      final clip = project.clipById('c1')!;
      expect(clip.durationMs, 2000);
      expect((clip.inPointMs, clip.outPointMs), (0, 4000));
    });

    test('a slower clip that would run into the next one is rejected',
        () async {
      // c1 lasts 4000 from 0, c2 starts at 6000: half speed needs 8000.
      final failure = _failure(
        await SetClipSpeed(projects)(
          projectId: 'p1',
          clipId: 'c1',
          speed: 0.5,
        ),
      );

      expect(failure, isA<Overlap>());
      expect(projects.saveCount, 0);
    });

    test('rejects speeds out of range', () async {
      expect(
        _failure(
          await SetClipSpeed(projects)(
            projectId: 'p1',
            clipId: 'c1',
            speed: 8,
          ),
        ),
        isA<InvalidSpeed>(),
      );
    });

    test('splitting a fast clip cuts the source at the right point', () async {
      await SetClipSpeed(projects)(projectId: 'p1', clipId: 'c1', speed: 2);
      final project = _ok(
        await SplitClip(projects, SequentialIdGenerator())(
          projectId: 'p1',
          clipId: 'c1',
          atMs: 500,
        ),
      );

      final clips = project.layerById('v1')!.clips;
      // 500 ms of timeline at 2x is 1000 ms of source.
      expect((clips[0].outPointMs, clips[1].inPointMs), (1000, 1000));
      expect((clips[0].durationMs, clips[1].durationMs), (500, 1500));
    });

    test('trimming the start of a fast clip keeps its end in place', () async {
      await SetClipSpeed(projects)(projectId: 'p1', clipId: 'c1', speed: 2);
      final project = _ok(
        await TrimClip(projects)(
          projectId: 'p1',
          clipId: 'c1',
          inPointMs: 1000,
          outPointMs: 4000,
        ),
      );

      final clip = project.clipById('c1')!;
      expect(clip.startMs, 500);
      expect(clip.range.endMs, 2000);
    });
  });

  group('fades', () {
    test('sets fades up to half the clip', () async {
      final project = _ok(
        await SetClipFades(projects)(
          projectId: 'p1',
          clipId: 'm1',
          inMs: 1000,
          outMs: 4000,
        ),
      );

      final clip = project.clipById('m1')!;
      expect((clip.fadeInMs, clip.fadeOutMs), (1000, 4000));
    });

    test('a fade longer than half the clip is rejected', () async {
      expect(
        _failure(
          await SetClipFades(projects)(
            projectId: 'p1',
            clipId: 'm1',
            inMs: 4001,
            outMs: 0,
          ),
        ),
        isA<InvalidFade>(),
      );
    });
  });

  group('crop', () {
    test('keeps part of the picture', () async {
      const crop = ClipCrop(left: 0.1, right: 0.2, top: 0.05);
      final project = _ok(
        await SetClipCrop(projects)(projectId: 'p1', clipId: 'c1', crop: crop),
      );

      expect(project.clipById('c1')!.crop, crop);
    });

    test('a crop that leaves almost nothing is rejected', () async {
      expect(
        _failure(
          await SetClipCrop(projects)(
            projectId: 'p1',
            clipId: 'c1',
            crop: const ClipCrop(left: 0.6, right: 0.38),
          ),
        ),
        isA<InvalidCrop>(),
      );
    });

    test('a centred crop to 9:16 keeps the middle of a 16:9 picture', () {
      final crop = ClipCrop.centred(9 / 16, 1920, 1080);
      expect(crop.top, 0);
      expect(crop.keptWidth, closeTo((9 / 16) / (16 / 9), 1e-9));
      expect(crop.left, closeTo(crop.right, 1e-9));
    });
  });

  test('an image lasts the duration it is given', () async {
    final withImage = buildFixtureProject();
    projects = InMemoryProjectRepository([withImage]);
    final failure = _failure(
      await SetImageDuration(projects)(
        projectId: 'p1',
        clipId: 'c1',
        durationMs: 2000,
      ),
    );
    expect(failure, isA<IncompatibleClip>());
    expect(minClipSpeed, lessThan(1));
  });
}
