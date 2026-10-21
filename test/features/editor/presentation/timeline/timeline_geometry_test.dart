import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/presentation/timeline/timeline_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/in_memory_editor_ports.dart';

const _clip = Clip(
  id: 'c',
  layerId: 'l',
  assetId: 'a',
  sourceUri: '/v.mp4',
  kind: MediaKind.video,
  startMs: 1000,
  inPointMs: 500,
  outPointMs: 2500,
  sourceDurationMs: 4000,
);

void main() {
  test('picks a round step wide enough for a label', () {
    expect(niceStepMs(0.1, 80), 1000);
    expect(niceStepMs(0.6, 80), 200);
    expect(niceStepMs(0.005, 80), 30000);
  });

  test('snaps to a close target and leaves a far time alone', () {
    final targets = [0, 4000, 6000];
    // 10 px at 0.1 px/ms reach 100 ms.
    expect(snapTime(3950, targets, 0.1), (ms: 4000, snapped: true));
    expect(snapTime(3800, targets, 0.1), (ms: 3800, snapped: false));
  });

  test('snap targets include the playhead and other clip edges only', () {
    final targets = snapTargets(buildFixtureProject(), 1234, 'c1');
    expect(targets, containsAll([0, 1234, 6000, 8000]));
    expect(targets, isNot(contains(4000)));
  });

  test('maps timeline time to source time, forwards and reversed', () {
    expect(sourceTimeAt(_clip, 1000), 500);
    expect(sourceTimeAt(_clip, 1500), 1000);
    final reversed = _clip.copyWith(reversed: true);
    expect(sourceTimeAt(reversed, 1000), 2500);
  });

  test('trimming the start stays inside the source and the minimum length', () {
    expect(trimStart(_clip, -2000), (inMs: 0, outMs: 2500));
    expect(
      trimStart(_clip, 5000),
      (inMs: 2500 - minClipDurationMs, outMs: 2500),
    );
  });

  test('trimming the end stays inside the source and the minimum length', () {
    expect(trimEnd(_clip, 9000), (inMs: 500, outMs: 4000));
    expect(trimEnd(_clip, -9000), (inMs: 500, outMs: 500 + minClipDurationMs));
  });

  test('the ruler steps read in milliseconds, seconds and minutes', () {
    expect(rulerStepMs(TimeScale.milliseconds.zoom), 50);
    expect(rulerStepMs(TimeScale.seconds.zoom), 1000);
    expect(rulerStepMs(TimeScale.minutes.zoom), 60000);
    // The closest view marks every 50 ms, the widest every two minutes.
    expect(rulerStepMs(maxZoom), 50);
    expect(rulerStepMs(minZoom), 120000);
  });

  test('the nearest time scale to a zoom', () {
    expect(TimeScale.nearest(0.08), TimeScale.seconds);
    expect(TimeScale.nearest(1), TimeScale.milliseconds);
    expect(TimeScale.nearest(0.002), TimeScale.minutes);
  });

  test('fitZoom makes the project fill the view, within the limits', () {
    // 10 s in a 524 px view with a 24 px margin: 0.05 px/ms.
    expect(fitZoom(10000, 524), closeTo(0.05, 1e-9));
    expect(fitZoom(0, 524), TimeScale.seconds.zoom);
    expect(fitZoom(100 * 3600 * 1000, 524), minZoom);
    expect(fitZoom(10, 524), maxZoom);
  });
}
