import 'dart:math' as math;

import 'package:cutter/features/editor/domain/time_range.dart';

/// Where the arrange actions of a selected clip send it on its layer.
enum ClipArrangement {
  /// Against the end of the clip before it, closing the gap to its left.
  closeGapBefore,

  /// Against the start of the clip after it, closing the gap to its right.
  closeGapAfter,

  /// The first free slot from the start of the timeline.
  toStart,

  /// After the last clip of the layer, or flush with the end of the project
  /// when the layer is shorter than it.
  toEnd,
}

bool _isFree(List<TimeRange> others, int startMs, int durationMs) {
  final range = TimeRange(startMs, durationMs);
  return others.every((other) => !other.overlaps(range));
}

/// The start closest to [desiredMs] at which a clip of [durationMs] fits
/// among [others] without sharing time with any of them; never before zero.
int nearestFreeStart(List<TimeRange> others, int durationMs, int desiredMs) {
  final desired = math.max(0, desiredMs);
  if (_isFree(others, desired, durationMs)) return desired;
  final candidates = <int>{
    0,
    for (final other in others) ...[
      other.endMs,
      if (other.startMs >= durationMs) other.startMs - durationMs,
    ],
  };
  int? best;
  for (final candidate in candidates) {
    if (!_isFree(others, candidate, durationMs)) continue;
    final distance = (candidate - desired).abs();
    if (best == null ||
        distance < (best - desired).abs() ||
        (distance == (best - desired).abs() && candidate < best)) {
      best = candidate;
    }
  }
  return best!;
}

/// The start a [clip] gets from [arrangement] among the other clips of its
/// layer, [others]; [projectEndMs] is where the whole project ends.
int arrangedStart(
  List<TimeRange> others,
  TimeRange clip,
  ClipArrangement arrangement,
  int projectEndMs,
) {
  switch (arrangement) {
    case ClipArrangement.closeGapBefore:
      var edge = 0;
      for (final other in others) {
        if (other.endMs <= clip.startMs) edge = math.max(edge, other.endMs);
      }
      return edge;
    case ClipArrangement.closeGapAfter:
      int? edge;
      for (final other in others) {
        if (other.startMs >= clip.endMs) {
          edge = edge == null ? other.startMs : math.min(edge, other.startMs);
        }
      }
      return edge == null ? clip.startMs : edge - clip.durationMs;
    case ClipArrangement.toStart:
      final starts = [0, for (final other in others) other.endMs]..sort();
      return starts.firstWhere(
        (start) => _isFree(others, start, clip.durationMs),
      );
    case ClipArrangement.toEnd:
      final lastEnd = others.fold<int>(0, (m, o) => math.max(m, o.endMs));
      return math.max(lastEnd, projectEndMs - clip.durationMs);
  }
}
