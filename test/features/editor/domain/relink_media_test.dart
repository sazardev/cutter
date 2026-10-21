import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/domain/relink_media.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_editor_ports.dart';

Clip _clip(String id, String uri, {int out = 5000, int start = 0}) => Clip(
      id: id,
      layerId: 'l1',
      assetId: 'old',
      sourceUri: uri,
      kind: MediaKind.video,
      startMs: start,
      inPointMs: 1000,
      outPointMs: out,
      sourceDurationMs: 8000,
    );

MediaAsset _asset({
  int durationMs = 9000,
  MediaKind kind = MediaKind.video,
  bool supported = true,
}) =>
    MediaAsset(
      id: 'new',
      uri: '/library/new.mp4',
      kind: kind,
      durationMs: durationMs,
      width: 1280,
      height: 720,
      supported: supported,
    );

void main() {
  final project = Project(
    id: 'p',
    name: 'P',
    layers: [
      Layer(
        id: 'l1',
        name: '',
        kind: MediaKind.video,
        clips: [
          _clip('a', '/gone.mp4'),
          _clip('b', '/gone.mp4', start: 5000),
          _clip('c', '/other.mp4', start: 10000),
        ],
      ),
    ],
  );

  test('checks kind, length and use before replacing', () {
    expect(relinkCheck(project, '/gone.mp4', _asset()), RelinkCheck.ok);
    expect(
      relinkCheck(project, '/gone.mp4', _asset(kind: MediaKind.audio)),
      RelinkCheck.wrongKind,
    );
    expect(
      relinkCheck(project, '/gone.mp4', _asset(durationMs: 4000)),
      RelinkCheck.tooShort,
    );
    expect(
      relinkCheck(project, '/gone.mp4', _asset(supported: false)),
      RelinkCheck.unreadable,
    );
    expect(relinkCheck(project, '/nobody.mp4', _asset()), RelinkCheck.notUsed);
  });

  test('every clip of the missing file points at the new one, trims kept',
      () async {
    final repository = InMemoryProjectRepository([project]);

    final result = await RelinkMedia(repository)(
      projectId: 'p',
      oldUri: '/gone.mp4',
      asset: _asset(),
    );

    final updated = (result as Ok<Project>).value;
    final clips = updated.layers.single.clips;
    expect(clips.map((c) => c.sourceUri), [
      '/library/new.mp4',
      '/library/new.mp4',
      '/other.mp4',
    ]);
    expect(clips.first.inPointMs, 1000);
    expect(clips.first.outPointMs, 5000);
    expect(clips.first.assetId, 'new');
    expect(
      (await repository.find('p'))!.layers.single.clips.first.sourceUri,
      '/library/new.mp4',
    );
  });

  test('a file that does not fit changes nothing', () async {
    final repository = InMemoryProjectRepository([project]);

    final result = await RelinkMedia(repository)(
      projectId: 'p',
      oldUri: '/gone.mp4',
      asset: _asset(durationMs: 100),
    );

    expect(result, isA<Err<Project>>());
    expect(repository.saveCount, 0);
  });
}
