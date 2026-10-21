import 'package:cutter/features/editor/data/sample_models.dart';
import 'package:cutter/features/editor/data/sample_project.dart';
import 'package:cutter/features/editor/presentation/editor_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EditorController controller;

  SampleLayer layerOf(String id) =>
      controller.project.layers.firstWhere((l) => l.id == id);

  SampleClip clipOf(String id) {
    for (final layer in controller.project.layers) {
      for (final clip in layer.clips) {
        if (clip.id == id) return clip;
      }
    }
    throw StateError('clip $id not found');
  }

  setUp(() {
    controller = EditorController(sampleProject());
  });

  group('trim (FR-6)', () {
    test('rejects zero duration and keeps the previous points', () {
      final outcome = controller.trim('clip-beach', 2000, 2000);

      expect(outcome, EditorOutcome.zeroDuration);
      final clip = clipOf('clip-beach');
      expect(clip.inMs, 0);
      expect(clip.outMs, 8000);
      expect(clip.durationMs, 8000);
    });

    test('rejects negative duration', () {
      final outcome = controller.trim('clip-beach', 3000, 2000);

      expect(outcome, EditorOutcome.zeroDuration);
      expect(clipOf('clip-beach').durationMs, 8000);
    });

    test('applies a valid trim and updates the duration', () {
      final outcome = controller.trim('clip-beach', 500, 6500);

      expect(outcome, EditorOutcome.ok);
      final clip = clipOf('clip-beach');
      expect(clip.inMs, 500);
      expect(clip.outMs, 6500);
      expect(clip.durationMs, 6000);
    });
  });

  group('split (FR-7)', () {
    test('at 3000 keeps total duration and adjacency', () {
      controller
        ..select('clip-beach')
        ..seek(3000);

      final outcome = controller.split();

      expect(outcome, EditorOutcome.ok);
      final clips = layerOf('layer-video').clips;
      expect(clips.length, 2);
      expect(clips[0].startMs, 0);
      expect(clips[0].endMs, clips[1].startMs);
      expect(clips[1].endMs, 8000);
      expect(clips[0].durationMs + clips[1].durationMs, 8000);
      expect(controller.selectedClipId, clips[1].id);
    });

    test('at the clip start is rejected and nothing changes', () {
      controller
        ..select('clip-beach')
        ..seek(0);

      expect(controller.canSplit, isFalse);
      expect(controller.split(), EditorOutcome.playheadOutsideClip);
      expect(layerOf('layer-video').clips.length, 1);
    });

    test('without a selection reports noClipSelected', () {
      expect(controller.split(), EditorOutcome.noClipSelected);
    });
  });

  group('move (FR-8)', () {
    test('overlap on the same layer is rejected', () {
      controller.loadProject(
        const SampleProject(
          id: 'p',
          name: 'P',
          layers: <SampleLayer>[
            SampleLayer(
              id: 'layer-video',
              kind: LayerKind.video,
              name: 'Video',
              clips: <SampleClip>[
                SampleClip(
                  id: 'a',
                  name: 'A',
                  kind: LayerKind.video,
                  startMs: 0,
                  durationMs: 2000,
                  inMs: 0,
                  outMs: 2000,
                ),
                SampleClip(
                  id: 'b',
                  name: 'B',
                  kind: LayerKind.video,
                  startMs: 3000,
                  durationMs: 2000,
                  inMs: 0,
                  outMs: 2000,
                ),
              ],
            ),
          ],
        ),
      );

      final outcome = controller.moveClip('b', 'layer-video', 1000);

      expect(outcome, EditorOutcome.overlap);
      expect(clipOf('b').startMs, 3000);
    });

    test('a layer of another kind is rejected', () {
      final outcome = controller.moveClip('clip-beach', 'layer-audio', 0);

      expect(outcome, EditorOutcome.wrongLayerKind);
      expect(layerOf('layer-video').clips.length, 1);
      expect(layerOf('layer-audio').clips.length, 1);
    });

    test('a free range on the same layer moves the clip', () {
      final outcome = controller.moveClip('clip-logo', 'layer-image', 4000);

      expect(outcome, EditorOutcome.ok);
      expect(clipOf('clip-logo').startMs, 4000);
    });
  });

  group('reverse (FR-9)', () {
    test('toggles on and off', () {
      controller.select('clip-beach');

      expect(controller.toggleReverse(), EditorOutcome.ok);
      expect(clipOf('clip-beach').reversed, isTrue);
      expect(clipOf('clip-beach').inMs, 0);
      expect(clipOf('clip-beach').outMs, 8000);

      controller.toggleReverse();
      expect(clipOf('clip-beach').reversed, isFalse);
    });

    test('without a selection reports noClipSelected', () {
      expect(controller.toggleReverse(), EditorOutcome.noClipSelected);
    });
  });

  group('layer volume (FR-14)', () {
    test('mute toggles on and off', () {
      controller.toggleLayerMute('layer-audio');
      expect(layerOf('layer-audio').muted, isTrue);

      controller.toggleLayerMute('layer-audio');
      expect(layerOf('layer-audio').muted, isFalse);
    });

    test('clip volume is clamped between 0 and 1', () {
      controller.setClipVolume('clip-song', 0);
      expect(clipOf('clip-song').volume, 0);

      controller.setClipVolume('clip-song', 3);
      expect(clipOf('clip-song').volume, 1);
    });
  });

  group('playback (FR-15)', () {
    test('seek clamps to the project range', () {
      controller.seek(-50);
      expect(controller.playheadMs, 0);

      controller.seek(999999);
      expect(controller.playheadMs, controller.project.durationMs);
    });

    test('tick advances while playing and stops at the end', () {
      controller.togglePlay();
      expect(controller.isPlaying, isTrue);

      controller.tick(1000);
      expect(controller.playheadMs, 1000);

      controller.tick(20000);
      expect(controller.playheadMs, controller.project.durationMs);
      expect(controller.isPlaying, isFalse);
    });

    test('tick does nothing while paused', () {
      controller.tick(500);

      expect(controller.playheadMs, 0);
    });

    test('play at the end restarts from zero', () {
      controller.seek(controller.project.durationMs);

      controller.togglePlay();

      expect(controller.isPlaying, isTrue);
      expect(controller.playheadMs, 0);
    });
  });

  group('import (FR-2)', () {
    test('unsupported media leaves the project unchanged', () {
      final before = controller.project;
      final broken =
          sampleMediaAssets.firstWhere((asset) => !asset.supported);

      final outcome = controller.addClipFromAsset(broken);

      expect(outcome, EditorOutcome.unsupportedMedia);
      expect(identical(controller.project, before), isTrue);
    });

    test('supported media is appended at the end of its layer', () {
      final city = sampleMediaAssets.firstWhere((a) => a.name == 'City.mp4');

      final outcome = controller.addClipFromAsset(city);

      expect(outcome, EditorOutcome.ok);
      final clips = layerOf('layer-video').clips;
      expect(clips.length, 2);
      expect(clips.last.startMs, 8000);
      expect(clips.last.durationMs, 6000);
    });
  });

  group('recording (FR-4)', () {
    test('lands on the audio layer at the playhead', () {
      final outcome = controller.addRecordedClip(
        kind: LayerKind.audio,
        startMs: 10000,
        durationMs: 2000,
      );

      expect(outcome, EditorOutcome.ok);
      final recorded = layerOf('layer-audio').clips.last;
      expect(recorded.startMs, 10000);
      expect(recorded.durationMs, 2000);
    });

    test('moves to the layer end instead of replacing a clip', () {
      controller.addRecordedClip(
        kind: LayerKind.audio,
        startMs: 2000,
        durationMs: 1000,
      );

      final clips = layerOf('layer-audio').clips;
      expect(clips.length, 2);
      expect(clips.last.startMs, 10000);
      expect(clipOf('clip-song').durationMs, 10000);
    });
  });

  group('layers and presets', () {
    test('reorderLayer moves a layer', () {
      controller.reorderLayer(0, 3);

      expect(
        controller.project.layers.map((l) => l.id).toList(),
        <String>['layer-image', 'layer-audio', 'layer-video'],
      );
    });

    test('a saved preset can be applied to another clip', () {
      controller
        ..setFilter('clip-beach', 'filter-noir')
        ..setAdjustment('clip-beach', 'brightness', 0.5)
        ..select('clip-beach');
      expect(controller.savePreset('Look'), EditorOutcome.ok);
      final presetId = controller.presets.single.id;

      controller.select('clip-logo');
      expect(controller.applyPreset(presetId), EditorOutcome.ok);

      final logo = clipOf('clip-logo');
      expect(logo.filterId, 'filter-noir');
      expect(logo.adjustments['brightness'], 0.5);
    });

    test('setFilter with null removes the filter', () {
      controller
        ..setFilter('clip-beach', 'filter-noir')
        ..setFilter('clip-beach', null);

      expect(clipOf('clip-beach').filterId, isNull);
    });
  });
}
