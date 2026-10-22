import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/clip_settings_use_cases.dart';
import 'package:cutter/features/editor/domain/clip_transform.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_editor_ports.dart';

Project _withImage() {
  final image = Clip(
    id: 'i1',
    layerId: 'img',
    assetId: 'file:///photo.jpg',
    sourceUri: 'file:///photo.jpg',
    kind: MediaKind.image,
    startMs: 1000,
    inPointMs: 0,
    outPointMs: 3000,
    sourceDurationMs: 3000,
    filterId: 'sepia',
    transform: const ClipTransform(x: 0.2, scale: 1.5),
    sourceWidth: 4000,
    sourceHeight: 3000,
  );
  return Project(
    id: 'p1',
    name: 'Images',
    layers: [
      Layer(id: 'img', name: '', kind: MediaKind.image, clips: [image]),
    ],
  );
}

void main() {
  test('swaps the file and keeps place, framing and look', () async {
    final repository = InMemoryProjectRepository([_withImage()]);

    final result = await ReplaceClipPicture(repository)(
      projectId: 'p1',
      clipId: 'i1',
      sourceUri: 'file:///cut.png',
      width: 2048,
      height: 1536,
    );

    final clip = (result as Ok<Project>).value.clipById('i1')!;
    expect(clip.sourceUri, 'file:///cut.png');
    expect(clip.assetId, 'file:///cut.png');
    expect((clip.sourceWidth, clip.sourceHeight), (2048, 1536));
    expect(clip.startMs, 1000);
    expect(clip.filterId, 'sepia');
    expect(clip.transform, const ClipTransform(x: 0.2, scale: 1.5));
  });

  test('refuses a video clip and saves nothing', () async {
    final repository = InMemoryProjectRepository([buildFixtureProject()]);
    final video = buildFixtureProject()
        .layers
        .expand((l) => l.clips)
        .firstWhere((c) => c.kind == MediaKind.video);

    final result = await ReplaceClipPicture(repository)(
      projectId: 'p1',
      clipId: video.id,
      sourceUri: 'file:///cut.png',
      width: 10,
      height: 10,
    );

    expect(result, isA<Err<Project>>());
    expect(
      repository.projects['p1']!.clipById(video.id)!.sourceUri,
      video.sourceUri,
    );
  });
}
