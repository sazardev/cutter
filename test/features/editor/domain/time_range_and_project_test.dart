import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/domain/time_range.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_editor_ports.dart';

void main() {
  group('TimeRange', () {
    test('end is start plus duration', () {
      expect(const TimeRange(1000, 500).endMs, 1500);
    });

    test('overlapping ranges overlap in both directions', () {
      const a = TimeRange(0, 1000);
      const b = TimeRange(500, 1000);
      expect(a.overlaps(b), isTrue);
      expect(b.overlaps(a), isTrue);
    });

    test('touching ranges do not overlap', () {
      const a = TimeRange(0, 1000);
      const b = TimeRange(1000, 500);
      expect(a.overlaps(b), isFalse);
      expect(b.overlaps(a), isFalse);
    });

    test('distant ranges do not overlap', () {
      expect(
        const TimeRange(0, 100).overlaps(const TimeRange(500, 100)),
        isFalse,
      );
    });

    test('a contained range overlaps its container', () {
      expect(
        const TimeRange(0, 1000).overlaps(const TimeRange(200, 100)),
        isTrue,
      );
    });

    test('containsStrictly excludes the boundaries', () {
      const range = TimeRange(1000, 1000);
      expect(range.containsStrictly(1000), isFalse);
      expect(range.containsStrictly(2000), isFalse);
      expect(range.containsStrictly(1001), isTrue);
      expect(range.containsStrictly(1999), isTrue);
      expect(range.containsStrictly(500), isFalse);
    });

    test('has value equality', () {
      expect(const TimeRange(1, 2), const TimeRange(1, 2));
      expect(const TimeRange(1, 2).hashCode, const TimeRange(1, 2).hashCode);
      expect(const TimeRange(1, 2), isNot(const TimeRange(1, 3)));
    });
  });

  group('Project lookups', () {
    final project = buildFixtureProject();

    test('layer order keeps index 0 as the front-most layer', () {
      expect(project.layers.map((layer) => layer.id), ['v1', 'a1']);
    });

    test('layerById finds a layer or returns null', () {
      expect(project.layerById('a1')?.kind, MediaKind.audio);
      expect(project.layerById('missing'), isNull);
    });

    test('clipById finds clips on any layer', () {
      expect(project.clipById('c2')?.startMs, 6000);
      expect(project.clipById('m1')?.layerId, 'a1');
      expect(project.clipById('missing'), isNull);
    });

    test('layerOfClip returns the owning layer', () {
      expect(project.layerOfClip('m1')?.id, 'a1');
      expect(project.layerOfClip('c1')?.id, 'v1');
      expect(project.layerOfClip('missing'), isNull);
    });

    test('durationMs is the largest clip end', () {
      expect(project.durationMs, 8000);
      expect(Project(id: 'e', name: 'Empty').durationMs, 0);
    });

    test('replaceLayer keeps order and swaps the layer', () {
      final muted = project.layerById('v1')!.copyWith(muted: true);
      final updated = project.replaceLayer(muted);
      expect(updated.layers.map((layer) => layer.id), ['v1', 'a1']);
      expect(updated.layerById('v1')!.muted, isTrue);
      expect(project.layerById('v1')!.muted, isFalse);
    });

    test('withLayers reorders layers', () {
      final reordered =
          project.withLayers([project.layers[1], project.layers[0]]);
      expect(reordered.layers.map((layer) => layer.id), ['a1', 'v1']);
      expect(reordered.id, project.id);
    });

    test('projects with the same content are equal', () {
      expect(buildFixtureProject(), buildFixtureProject());
    });
  });

  group('Layer', () {
    test('clips are kept sorted by start time', () {
      final project = buildFixtureProject();
      final c1 = project.clipById('c1')!;
      final c2 = project.clipById('c2')!;
      final layer = Layer(
        id: 'v1',
        name: 'Video',
        kind: MediaKind.video,
        clips: [c2, c1],
      );
      expect(layer.clips.map((clip) => clip.id), ['c1', 'c2']);
      expect(
        layer.withClips([c2, c1]).clips.map((clip) => clip.id),
        ['c1', 'c2'],
      );
    });

    test('effective volume is layer volume times clip volume', () {
      final project = buildFixtureProject();
      final audio = project.layerById('a1')!;
      final clip = project.clipById('m1')!;
      expect(audio.effectiveVolumeOf(clip), closeTo(0.8, 1e-9));

      final halved = audio.copyWith(volume: 0.5);
      expect(halved.effectiveVolumeOf(clip), closeTo(0.4, 1e-9));
    });

    test('effective volume is zero when the layer is muted', () {
      final project = buildFixtureProject();
      final audio = project.layerById('a1')!.copyWith(muted: true);
      expect(audio.effectiveVolumeOf(project.clipById('m1')!), 0);
    });

    test('a clip at volume zero is silent while others are unaffected', () {
      final project = buildFixtureProject();
      final video = project.layerById('v1')!;
      final silent = project.clipById('c1')!.copyWith(volume: 0);
      expect(video.effectiveVolumeOf(silent), 0);
      expect(video.effectiveVolumeOf(project.clipById('c2')!), 1);
    });
  });

  group('Clip', () {
    test('duration and range come from the in and out points', () {
      final clip = buildFixtureProject().clipById('c1')!;
      expect(clip.durationMs, 4000);
      expect(clip.range, const TimeRange(0, 4000));
    });

    test('copyWith can clear the filter', () {
      final clip = buildFixtureProject().clipById('c1')!;
      final filtered = clip.copyWith(filterId: 'sepia');
      expect(filtered.filterId, 'sepia');
      expect(filtered.copyWith(clearFilter: true).filterId, isNull);
    });
  });
}
