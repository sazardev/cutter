import 'package:cutter/features/editor/domain/clip_placement.dart';
import 'package:cutter/features/editor/domain/time_range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const others = [TimeRange(0, 4000), TimeRange(6000, 2000)];

  group('nearestFreeStart', () {
    test('keeps a start that is already free', () {
      expect(nearestFreeStart(others, 1000, 4200), 4200);
    });

    test('moves a start that overlaps to the closest free one', () {
      // 3500 overlaps the first clip; 4000 is the closest free start.
      expect(nearestFreeStart(others, 1000, 3500), 4000);
      // 5500 would run into the second clip; 5000 ends exactly at it.
      expect(nearestFreeStart(others, 1000, 5500), 5000);
    });

    test('goes past the last clip when no gap is wide enough', () {
      expect(nearestFreeStart(others, 3000, 4500), 8000);
    });

    test('never returns a negative start', () {
      expect(nearestFreeStart(others, 1000, -300), 4000);
      expect(nearestFreeStart(const [], 1000, -300), 0);
    });
  });

  group('arrangedStart', () {
    const clip = TimeRange(4500, 1000);
    const around = [TimeRange(0, 4000), TimeRange(6000, 2000)];

    test('close gap before packs against the clip before', () {
      expect(
        arrangedStart(around, clip, ClipArrangement.closeGapBefore, 8000),
        4000,
      );
    });

    test('close gap before goes to zero when nothing is before', () {
      expect(
        arrangedStart(
          const [TimeRange(6000, 2000)],
          clip,
          ClipArrangement.closeGapBefore,
          8000,
        ),
        0,
      );
    });

    test('close gap after packs against the clip after', () {
      expect(
        arrangedStart(around, clip, ClipArrangement.closeGapAfter, 8000),
        5000,
      );
    });

    test('close gap after stays put when nothing is after', () {
      expect(
        arrangedStart(
          const [TimeRange(0, 4000)],
          clip,
          ClipArrangement.closeGapAfter,
          8000,
        ),
        4500,
      );
    });

    test('to start takes the first free slot from zero', () {
      expect(
        arrangedStart(
          const [TimeRange(6000, 2000)],
          clip,
          ClipArrangement.toStart,
          8000,
        ),
        0,
      );
      expect(
        arrangedStart(around, clip, ClipArrangement.toStart, 8000),
        4000,
      );
    });

    test('to end goes after the last clip', () {
      expect(
        arrangedStart(around, clip, ClipArrangement.toEnd, 8000),
        8000,
      );
    });

    test('to end lines a lone clip up with the end of the project', () {
      expect(
        arrangedStart(const [], clip, ClipArrangement.toEnd, 8000),
        7000,
      );
    });
  });
}
