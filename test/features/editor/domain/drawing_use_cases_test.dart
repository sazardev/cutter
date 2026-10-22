import 'package:cutter/features/editor/domain/clip_drawing.dart';
import 'package:cutter/features/editor/domain/drawing_use_cases.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_editor_ports.dart';

const _ink = ClipDrawing([
  DrawingStroke(color: 0xFF000000, width: 0.02, points: [0.1, 0.1, 0.9, 0.9]),
]);

Project _valueOf(EditorResult<Project> result) => (result as Ok<Project>).value;

void main() {
  late InMemoryProjectRepository repository;
  late AddDrawingClip add;

  setUp(() {
    repository = InMemoryProjectRepository([buildFixtureProject()]);
    add = AddDrawingClip(repository, SequentialIdGenerator());
  });

  Future<EditorResult<Project>> addAt(int startMs, {ClipDrawing? drawing}) =>
      add(
        projectId: 'p1',
        drawing: drawing ?? _ink,
        sourceUri: '/drawings/d$startMs.png',
        width: 1080,
        height: 1920,
        startMs: startMs,
      );

  test('puts the drawing on a new image layer in front', () async {
    final project = _valueOf(await addAt(500));

    final front = project.layers.first;
    expect(front.kind, MediaKind.image);
    final clip = front.clips.single;
    expect(clip.drawing, _ink);
    expect(clip.kind, MediaKind.image);
    expect((clip.startMs, clip.durationMs), (500, defaultDrawingDurationMs));
    expect(clip.sourceUri, '/drawings/d500.png');
    expect((clip.sourceWidth, clip.sourceHeight), (1080, 1920));
  });

  test('a later drawing shares the layer, an overlapping one does not',
      () async {
    await addAt(0);
    final after = _valueOf(await addAt(defaultDrawingDurationMs + 100));
    final imageLayers =
        after.layers.where((l) => l.kind == MediaKind.image).toList();
    expect(imageLayers, hasLength(1));
    expect(imageLayers.single.clips, hasLength(2));

    final overlapping = _valueOf(await addAt(1000));
    expect(
      overlapping.layers.where((l) => l.kind == MediaKind.image),
      hasLength(2),
    );
  });

  test('refuses a blank drawing and a negative start', () async {
    expect(
      await addAt(0, drawing: ClipDrawing.empty),
      isA<Err<Project>>()
          .having((e) => e.failure, 'failure', isA<InvalidDrawing>()),
    );
    expect(
      await addAt(-1),
      isA<Err<Project>>()
          .having((e) => e.failure, 'failure', isA<NegativeStart>()),
    );
    expect(
      repository.projects['p1']!.layers.every((l) => l.kind != MediaKind.image),
      isTrue,
    );
  });

  test('editing replaces strokes and picture but keeps the clip', () async {
    final first = _valueOf(await addAt(500));
    final id = first.layers.first.clips.single.id;
    const more = ClipDrawing([
      DrawingStroke(color: 0xFF00FF00, width: 0.05, points: [0.2, 0.2]),
    ]);

    final result = await SetClipDrawing(repository)(
      projectId: 'p1',
      clipId: id,
      drawing: more,
      sourceUri: '/drawings/new.png',
      width: 540,
      height: 960,
    );

    final clip = _valueOf(result).clipById(id)!;
    expect(clip.drawing, more);
    expect(clip.sourceUri, '/drawings/new.png');
    expect((clip.sourceWidth, clip.sourceHeight), (540, 960));
    expect((clip.startMs, clip.durationMs), (500, defaultDrawingDurationMs));
  });

  test('editing refuses a clip that is not a drawing', () async {
    final clip = buildFixtureProject()
        .layers
        .expand((l) => l.clips)
        .firstWhere((c) => c.kind == MediaKind.video);

    final result = await SetClipDrawing(repository)(
      projectId: 'p1',
      clipId: clip.id,
      drawing: _ink,
      sourceUri: '/x.png',
      width: 1,
      height: 1,
    );

    expect(
      result,
      isA<Err<Project>>()
          .having((e) => e.failure, 'failure', isA<InvalidDrawing>()),
    );
  });
}
