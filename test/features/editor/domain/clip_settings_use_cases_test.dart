import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/clip_settings_use_cases.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/layer_use_cases.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_editor_ports.dart';

Project _stored(InMemoryProjectRepository repository) =>
    repository.projects['p1']!;

Project _valueOf(EditorResult<Project> result) => (result as Ok<Project>).value;

Matcher _failsWith(EditorFailure failure) => isA<Err<Project>>().having(
      (err) => err.failure,
      'failure',
      failure,
    );

Project _projectWithImage() {
  const image = Clip(
    id: 'i1',
    layerId: 'img',
    assetId: 'asset-image',
    sourceUri: 'file:///photo.jpg',
    kind: MediaKind.image,
    startMs: 0,
    inPointMs: 0,
    outPointMs: 3000,
    sourceDurationMs: 3000,
  );
  return Project(
    id: 'p1',
    name: 'Images',
    layers: [
      Layer(
        id: 'img',
        name: 'Images',
        kind: MediaKind.image,
        clips: const [image],
      ),
    ],
  );
}

void main() {
  late InMemoryProjectRepository repository;

  setUp(() {
    repository = InMemoryProjectRepository([buildFixtureProject()]);
  });

  group('SetClipReverse', () {
    test('reverses a video clip and keeps its in and out points', () async {
      final result = await SetClipReverse(repository)(
        projectId: 'p1',
        clipId: 'c1',
        enabled: true,
      );

      final clip = _valueOf(result).clipById('c1')!;
      expect(clip.reversed, isTrue);
      expect(clip.inPointMs, 0);
      expect(clip.outPointMs, 4000);
      expect(_stored(repository).clipById('c1')!.reversed, isTrue);
    });

    test('plays forward again when toggled off, in and out unchanged',
        () async {
      final reverse = SetClipReverse(repository);
      await reverse(projectId: 'p1', clipId: 'c1', enabled: true);
      final result =
          await reverse(projectId: 'p1', clipId: 'c1', enabled: false);

      final clip = _valueOf(result).clipById('c1')!;
      expect(clip.reversed, isFalse);
      expect(clip.inPointMs, 0);
      expect(clip.outPointMs, 4000);
    });

    test('rejects an audio clip and saves nothing', () async {
      final result = await SetClipReverse(repository)(
        projectId: 'p1',
        clipId: 'm1',
        enabled: true,
      );

      expect(result, _failsWith(const NotReversible()));
      expect(repository.saveCount, 0);
      expect(_stored(repository).clipById('m1')!.reversed, isFalse);
    });

    test('rejects an image clip', () async {
      repository = InMemoryProjectRepository([_projectWithImage()]);

      final result = await SetClipReverse(repository)(
        projectId: 'p1',
        clipId: 'i1',
        enabled: true,
      );

      expect(result, _failsWith(const NotReversible()));
      expect(repository.saveCount, 0);
    });

    test('reports unknown project and clip', () async {
      final reverse = SetClipReverse(repository);

      expect(
        await reverse(projectId: 'nope', clipId: 'c1', enabled: true),
        _failsWith(const ProjectNotFound('nope')),
      );
      expect(
        await reverse(projectId: 'p1', clipId: 'nope', enabled: true),
        _failsWith(const ClipNotFound('nope')),
      );
      expect(repository.saveCount, 0);
    });
  });

  group('SetClipVolume', () {
    test('sets the volume of one clip only', () async {
      final result = await SetClipVolume(repository)(
        projectId: 'p1',
        clipId: 'c1',
        volume: 0,
      );

      final project = _valueOf(result);
      expect(project.clipById('c1')!.volume, 0);
      expect(project.clipById('c2')!.volume, 1);
      expect(project.clipById('m1')!.volume, 0.8);
      expect(_stored(repository).clipById('c1')!.volume, 0);
    });

    test('accepts the range limits', () async {
      final setVolume = SetClipVolume(repository);

      final low = await setVolume(projectId: 'p1', clipId: 'c1', volume: 0);
      final high = await setVolume(projectId: 'p1', clipId: 'c1', volume: 1);

      expect(low, isA<Ok<Project>>());
      expect(high, isA<Ok<Project>>());
    });

    test('rejects volumes outside 0 to 1 and saves nothing', () async {
      final setVolume = SetClipVolume(repository);

      expect(
        await setVolume(projectId: 'p1', clipId: 'c1', volume: 1.5),
        _failsWith(const InvalidVolume()),
      );
      expect(
        await setVolume(projectId: 'p1', clipId: 'c1', volume: -0.1),
        _failsWith(const InvalidVolume()),
      );
      expect(
        await setVolume(projectId: 'p1', clipId: 'c1', volume: double.nan),
        _failsWith(const InvalidVolume()),
      );
      expect(repository.saveCount, 0);
    });
  });

  group('SetClipFilter', () {
    test('applies a filter to a video clip', () async {
      final result = await SetClipFilter(repository)(
        projectId: 'p1',
        clipId: 'c1',
        filterId: 'warm',
      );

      expect(_valueOf(result).clipById('c1')!.filterId, 'warm');
    });

    test('applies a filter to an image clip', () async {
      repository = InMemoryProjectRepository([_projectWithImage()]);

      final result = await SetClipFilter(repository)(
        projectId: 'p1',
        clipId: 'i1',
        filterId: 'mono',
      );

      expect(_valueOf(result).clipById('i1')!.filterId, 'mono');
    });

    test('removes the filter when the id is null', () async {
      final setFilter = SetClipFilter(repository);
      await setFilter(projectId: 'p1', clipId: 'c1', filterId: 'warm');

      final result = await setFilter(projectId: 'p1', clipId: 'c1');

      expect(_valueOf(result).clipById('c1')!.filterId, isNull);
      expect(_stored(repository).clipById('c1')!.filterId, isNull);
    });

    test('rejects a filter on an audio clip and saves nothing', () async {
      final result = await SetClipFilter(repository)(
        projectId: 'p1',
        clipId: 'm1',
        filterId: 'warm',
      );

      expect(result, _failsWith(const IncompatibleClip()));
      expect(repository.saveCount, 0);
    });
  });

  group('SetClipAdjustments', () {
    test('stores the confirmed adjustments on the clip', () async {
      final result = await SetClipAdjustments(repository)(
        projectId: 'p1',
        clipId: 'c1',
        adjustments: {'brightness': 0.5, 'contrast': -1, 'saturation': 1},
      );

      expect(
        _valueOf(result).clipById('c1')!.adjustments,
        {'brightness': 0.5, 'contrast': -1.0, 'saturation': 1.0},
      );
    });

    test('stores the effect strengths next to the color adjustments', () async {
      final result = await SetClipAdjustments(repository)(
        projectId: 'p1',
        clipId: 'c1',
        adjustments: {'brightness': 0.5, 'blur': 0.4, 'vignette': 1},
      );

      expect(
        _valueOf(result).clipById('c1')!.adjustments,
        {'brightness': 0.5, 'blur': 0.4, 'vignette': 1.0},
      );
    });

    test('every effect key is accepted', () async {
      final result = await SetClipAdjustments(repository)(
        projectId: 'p1',
        clipId: 'c1',
        adjustments: {for (final key in effectKeys) key: 0.5},
      );

      expect(_valueOf(result).clipById('c1')!.adjustments.keys, effectKeys);
    });

    test('replaces the previous adjustments', () async {
      final setAdjustments = SetClipAdjustments(repository);
      await setAdjustments(
        projectId: 'p1',
        clipId: 'c1',
        adjustments: {'brightness': 0.5},
      );

      final result = await setAdjustments(
        projectId: 'p1',
        clipId: 'c1',
        adjustments: {'contrast': 0.2},
      );

      expect(_valueOf(result).clipById('c1')!.adjustments, {'contrast': 0.2});
    });

    test('rejects a key outside the confirmed set', () async {
      final result = await SetClipAdjustments(repository)(
        projectId: 'p1',
        clipId: 'c1',
        adjustments: {'sharpness': 0.1},
      );

      expect(result, _failsWith(const UnknownAdjustment('sharpness')));
      expect(repository.saveCount, 0);
    });

    test('rejects values outside -1 to 1', () async {
      final setAdjustments = SetClipAdjustments(repository);

      expect(
        await setAdjustments(
          projectId: 'p1',
          clipId: 'c1',
          adjustments: {'brightness': 1.01},
        ),
        _failsWith(const AdjustmentOutOfRange('brightness')),
      );
      expect(
        await setAdjustments(
          projectId: 'p1',
          clipId: 'c1',
          adjustments: {'contrast': double.nan},
        ),
        _failsWith(const AdjustmentOutOfRange('contrast')),
      );
      expect(repository.saveCount, 0);
    });
  });

  group('SetLayerVolume', () {
    test('sets layer volume and combines it with the clip volume', () async {
      final result = await SetLayerVolume(repository)(
        projectId: 'p1',
        layerId: 'a1',
        volume: 0.5,
        muted: false,
      );

      final layer = _valueOf(result).layerById('a1')!;
      expect(layer.volume, 0.5);
      expect(layer.effectiveVolumeOf(layer.clips.first), closeTo(0.4, 1e-9));
    });

    test('muting silences every clip of the layer only', () async {
      final result = await SetLayerVolume(repository)(
        projectId: 'p1',
        layerId: 'a1',
        volume: 1,
        muted: true,
      );

      final project = _valueOf(result);
      final audio = project.layerById('a1')!;
      final video = project.layerById('v1')!;
      expect(audio.effectiveVolumeOf(audio.clips.first), 0);
      expect(video.effectiveVolumeOf(video.clips.first), 1);
    });

    test('rejects an invalid volume and saves nothing', () async {
      final result = await SetLayerVolume(repository)(
        projectId: 'p1',
        layerId: 'a1',
        volume: 2,
        muted: false,
      );

      expect(result, _failsWith(const InvalidVolume()));
      expect(repository.saveCount, 0);
    });

    test('reports unknown project and layer', () async {
      final setVolume = SetLayerVolume(repository);

      expect(
        await setVolume(
          projectId: 'nope',
          layerId: 'a1',
          volume: 1,
          muted: false,
        ),
        _failsWith(const ProjectNotFound('nope')),
      );
      expect(
        await setVolume(
          projectId: 'p1',
          layerId: 'nope',
          volume: 1,
          muted: false,
        ),
        _failsWith(const LayerNotFound('nope')),
      );
      expect(repository.saveCount, 0);
    });
  });
}
