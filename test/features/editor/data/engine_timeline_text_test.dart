import 'package:cutter/core/engine/media_engine.dart';
import 'package:cutter/features/editor/data/engine_timeline.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/clip_text.dart';
import 'package:cutter/features/editor/domain/clip_transform.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

const _text = ClipText(
  content: 'Hola',
  font: 'anton',
  size: 0.1,
  color: 0xFFFF0000,
  italic: true,
  align: ClipTextAlign.right,
  strokeWidth: 0.1,
  shadow: 0.7,
  background: 0x80000000,
  animation: ClipTextAnimation.slideUp,
);

Clip _clip({ClipTransform transform = const ClipTransform()}) => Clip(
      id: 't1',
      layerId: 'lt',
      assetId: '',
      sourceUri: '',
      kind: MediaKind.text,
      startMs: 1000,
      inPointMs: textSourceSpanMs,
      outPointMs: textSourceSpanMs + 2000,
      sourceDurationMs: 2 * textSourceSpanMs,
      sourceWidth: 400,
      sourceHeight: 100,
      transform: transform,
      text: _text,
    );

Project _project(Clip clip) => Project(
      id: 'p',
      name: 'p',
      layers: [
        Layer(id: 'lt', name: '', kind: MediaKind.text, clips: [clip]),
      ],
    );

void main() {
  test('a text clip reaches the engine as a text layer with its look', () {
    final timeline = engineTimelineOf(_project(_clip()));

    final layer = timeline.layers.single;
    expect(layer.kind, EngineMediaKind.text);
    final clip = layer.clips.single;
    expect(clip.kind, EngineMediaKind.text);
    expect(clip.startMs, 1000);
    expect(clip.outMs - clip.inMs, 2000);
    final spec = clip.text!;
    expect(spec.content, 'Hola');
    expect(spec.font, 'anton');
    expect(spec.color, 0xFFFF0000);
    expect(spec.italic, isTrue);
    expect(spec.align, TextAlign.right);
    expect(spec.strokeWidth, 0.1);
    expect(spec.background, 0x80000000);
    expect(spec.animation, TextAnimation.slideUp);
  });

  test('a text being edited shows its draft without touching the project', () {
    final draft = _text.copyWith(content: 'Adiós', color: 0xFF00FF00);
    final timeline = engineTimelineOf(
      _project(_clip()),
      textOverrides: {'t1': draft},
    );

    expect(timeline.layers.single.clips.single.text!.content, 'Adiós');
    expect(timeline.layers.single.clips.single.text!.color, 0xFF00FF00);
  });

  test('the frame of a text grows with the canvas, not with a fit', () {
    final clip = _clip(transform: const ClipTransform(x: 0.25, scale: 2));

    final small = placementOf(clip, clip.transform, 540, 1000)!;
    final big = placementOf(clip, clip.transform, 1080, 2000)!;

    // 400x100 at the 1000 px reference, twice as big when scaled by 2.
    expect(small.width, 800);
    expect(small.height, 200);
    expect(big.width, 1600);
    expect(small.cx, 540 / 2 + 0.25 * 540);
  });
}
