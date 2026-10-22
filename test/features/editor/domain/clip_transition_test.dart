import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/clip_transition.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_editor_ports.dart';

Clip _clip(
  String id,
  int start,
  int length, {
  MediaKind kind = MediaKind.video,
}) =>
    Clip(
      id: id,
      layerId: 'l',
      assetId: 'a',
      sourceUri: '/$id',
      kind: kind,
      startMs: start,
      inPointMs: 0,
      outPointMs: length,
      sourceDurationMs: length,
    );

Project _project(List<Clip> clips, {MediaKind kind = MediaKind.video}) =>
    Project(
      id: 'p',
      name: 'P',
      layers: [Layer(id: 'l', name: '', kind: kind, clips: clips)],
    );

Clip _find(Project project, String id) => project.clipById(id)!;

void main() {
  test('every transition pairs known animations', () {
    for (final kind in TransitionKind.values) {
      expect(clipAnimationIds, contains(kind.animOut), reason: kind.name);
      expect(clipAnimationIds, contains(kind.animIn), reason: kind.name);
    }
  });

  group('previousNeighbour', () {
    final layer = Layer(
      id: 'l',
      name: '',
      kind: MediaKind.video,
      clips: [
        _clip('a', 0, 4000),
        _clip('b', 4100, 3000),
        _clip('c', 9000, 2000),
      ],
    );

    test('is the clip that ends right before, within a small gap', () {
      expect(previousNeighbour(layer, layer.clips[1])?.id, 'a');
      expect(previousNeighbour(layer, layer.clips[0]), isNull);
    });

    test('is null across a long gap', () {
      expect(previousNeighbour(layer, layer.clips[2]), isNull);
    });
  });

  group('ApplyTransition', () {
    test('sets the exit of the first and the entrance of the second', () async {
      final repository = InMemoryProjectRepository([
        _project([_clip('a', 0, 4000), _clip('b', 4000, 3000)]),
      ]);

      final result = await ApplyTransition(repository)(
        projectId: 'p',
        clipId: 'b',
        kind: TransitionKind.pushLeft,
        durationMs: 600,
      );

      final project = (result as Ok<Project>).value;
      final a = _find(project, 'a');
      final b = _find(project, 'b');
      expect(a.animOut, 'slide_left');
      expect(a.animOutMs, 600);
      expect(b.animIn, 'slide_right');
      expect(b.animInMs, 600);
      // The sound follows: it fades out and in over the same length.
      expect(a.fadeOutMs, 600);
      expect(b.fadeInMs, 600);
      expect(transitionBetween(a, b), TransitionKind.pushLeft);
      expect(repository.saveCount, 1);
    });

    test('cuts the length to half of a short clip', () async {
      final repository = InMemoryProjectRepository([
        _project([_clip('a', 0, 800), _clip('b', 800, 4000)]),
      ]);

      final result = await ApplyTransition(repository)(
        projectId: 'p',
        clipId: 'b',
        kind: TransitionKind.dip,
        durationMs: 1500,
      );

      final project = (result as Ok<Project>).value;
      expect(_find(project, 'a').animOutMs, 400);
      expect(_find(project, 'b').animInMs, 1500);
    });

    test('leaves the sound alone when asked, and pictures have none', () async {
      final repository = InMemoryProjectRepository([
        _project([
          _clip('a', 0, 3000, kind: MediaKind.image),
          _clip('b', 3000, 3000, kind: MediaKind.image),
        ]),
      ]);

      final result = await ApplyTransition(repository)(
        projectId: 'p',
        clipId: 'b',
        kind: TransitionKind.zoomThrough,
        durationMs: 500,
        fadeSound: false,
      );

      final project = (result as Ok<Project>).value;
      expect(_find(project, 'a').fadeOutMs, 0);
      expect(_find(project, 'b').fadeInMs, 0);
      expect(_find(project, 'a').animOut, 'zoom_out');
    });

    test('on sound it only fades: there is no picture to animate', () async {
      final repository = InMemoryProjectRepository([
        _project(
          [
            _clip('a', 0, 4000, kind: MediaKind.audio),
            _clip('b', 4000, 4000, kind: MediaKind.audio),
          ],
          kind: MediaKind.audio,
        ),
      ]);

      final result = await ApplyTransition(repository)(
        projectId: 'p',
        clipId: 'b',
        kind: TransitionKind.dip,
        durationMs: 1000,
      );

      final project = (result as Ok<Project>).value;
      expect(_find(project, 'a').animOut, isNull);
      expect(_find(project, 'a').fadeOutMs, 1000);
      expect(_find(project, 'b').fadeInMs, 1000);
    });

    test('is refused with no neighbour or a bad length', () async {
      final repository = InMemoryProjectRepository([
        _project([_clip('a', 0, 3000), _clip('b', 9000, 3000)]),
      ]);
      final apply = ApplyTransition(repository);

      expect(
        await apply(
          projectId: 'p',
          clipId: 'b',
          kind: TransitionKind.dip,
          durationMs: 500,
        ),
        isA<Err<Project>>(),
      );
      expect(
        await apply(
          projectId: 'p',
          clipId: 'a',
          kind: TransitionKind.dip,
          durationMs: 500,
        ),
        isA<Err<Project>>(),
      );
      expect(
        await apply(
          projectId: 'p',
          clipId: 'b',
          kind: TransitionKind.dip,
          durationMs: 50,
        ),
        isA<Err<Project>>(),
      );
      expect(repository.saveCount, 0);
    });
  });

  test('RemoveTransition clears both sides of the join', () async {
    final repository = InMemoryProjectRepository([
      _project([_clip('a', 0, 4000), _clip('b', 4000, 3000)]),
    ]);
    await ApplyTransition(repository)(
      projectId: 'p',
      clipId: 'b',
      kind: TransitionKind.pop,
      durationMs: 400,
    );

    final result = await RemoveTransition(repository)(
      projectId: 'p',
      clipId: 'b',
    );

    final project = (result as Ok<Project>).value;
    final a = _find(project, 'a');
    final b = _find(project, 'b');
    expect(a.animOut, isNull);
    expect(a.fadeOutMs, 0);
    expect(b.animIn, isNull);
    expect(b.fadeInMs, 0);
    expect(transitionBetween(a, b), isNull);
  });
}
