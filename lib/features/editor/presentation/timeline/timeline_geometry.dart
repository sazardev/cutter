import 'dart:math' as math;

import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/project.dart';

/// Widest view, in logical pixels per millisecond (1 px per second, an hour
/// in about 3600 px).
const double minZoom = 0.001;

/// Closest view (2000 px per second, a frame at 60 fps is over 30 px).
const double maxZoom = 2;

/// Zoom a new editor opens at (80 px per second).
const double defaultZoom = 0.08;

/// How close, in logical pixels, an edge must come to snap.
const double snapDistancePx = 10;

const List<int> _steps = [
  100,
  200,
  250,
  500,
  1000,
  2000,
  5000,
  10000,
  15000,
  30000,
  60000,
  120000,
  300000,
];

/// Ready-made views of the timeline, each tuned so its ruler reads in one
/// unit.
enum TimeScale {
  /// Milliseconds: marks every 50 ms.
  milliseconds(1.5),

  /// Seconds: one mark per second.
  seconds(0.1),

  /// Minutes: one mark per minute.
  minutes(0.0015);

  const TimeScale(this.zoom);

  /// Logical pixels per millisecond.
  final double zoom;

  /// The scale whose zoom is closest to [zoom] on a logarithmic scale.
  static TimeScale nearest(double zoom) {
    TimeScale? best;
    var bestDistance = double.infinity;
    for (final scale in values) {
      final distance = (math.log(zoom) - math.log(scale.zoom)).abs();
      if (distance < bestDistance) {
        best = scale;
        bestDistance = distance;
      }
    }
    return best!;
  }
}

/// The zoom at which a project of [durationMs] fills [viewportPx], leaving
/// [marginPx] free at the end.
double fitZoom(int durationMs, double viewportPx, {double marginPx = 24}) {
  if (durationMs <= 0 || viewportPx <= marginPx) return TimeScale.seconds.zoom;
  return ((viewportPx - marginPx) / durationMs).clamp(minZoom, maxZoom);
}

/// Pixels the ruler wants between two labels.
const double rulerLabelSpacingPx = 72;

const List<int> _rulerSteps = [
  10,
  20,
  50,
  100,
  200,
  250,
  500,
  1000,
  2000,
  5000,
  10000,
  15000,
  30000,
  60000,
  120000,
  300000,
  600000,
  1800000,
  3600000,
];

/// The round step, in milliseconds, between two ruler labels at [zoom]: the
/// smallest that is at least [rulerLabelSpacingPx] wide, down to 10 ms.
int rulerStepMs(double zoom) {
  for (final step in _rulerSteps) {
    if (step * zoom >= rulerLabelSpacingPx) return step;
  }
  return _rulerSteps.last;
}

/// The smallest round step, in milliseconds, that is at least [minPx]
/// logical pixels wide at [zoom].
int niceStepMs(double zoom, double minPx) {
  for (final step in _steps) {
    if (step * zoom >= minPx) return step;
  }
  return _steps.last;
}

/// The times a dragged edge snaps to: zero, the playhead and the edges of
/// every clip except [ignoredClipId].
List<int> snapTargets(Project project, int playheadMs, String ignoredClipId) {
  return [
    0,
    playheadMs,
    for (final layer in project.layers)
      for (final clip in layer.clips)
        if (clip.id != ignoredClipId) ...[clip.startMs, clip.range.endMs],
  ];
}

/// [ms] moved onto the closest of [targets] within [snapDistancePx] at
/// [zoom], or unchanged.
({int ms, bool snapped}) snapTime(int ms, List<int> targets, double zoom) {
  final reach = snapDistancePx / zoom;
  int? best;
  for (final target in targets) {
    final distance = (target - ms).abs();
    if (distance <= reach && (best == null || distance < (best - ms).abs())) {
      best = target;
    }
  }
  return best == null ? (ms: ms, snapped: false) : (ms: best, snapped: true);
}

/// The source time shown at timeline time [timelineMs] of [clip].
int sourceTimeAt(Clip clip, int timelineMs) {
  final offset = clip.sourceSpanOf(timelineMs - clip.startMs);
  return clip.reversed ? clip.outPointMs - offset : clip.inPointMs + offset;
}

/// The in and out points of [clip] after dragging its start edge by
/// [deltaMs], kept inside the source and at least the minimum length.
///
/// [deltaMs] is in timeline time; the source moves by it at the clip's
/// speed.
({int inMs, int outMs}) trimStart(Clip clip, int deltaMs) {
  final earliest = -clip.inPointMs;
  final latest =
      clip.outPointMs - clip.inPointMs - clip.sourceSpanOf(minClipDurationMs);
  final delta = clip.sourceSpanOf(deltaMs).clamp(earliest, latest);
  return (inMs: clip.inPointMs + delta, outMs: clip.outPointMs);
}

/// The in and out points of [clip] after dragging its end edge by [deltaMs].
({int inMs, int outMs}) trimEnd(Clip clip, int deltaMs) {
  final shortest =
      clip.sourceSpanOf(minClipDurationMs) - (clip.outPointMs - clip.inPointMs);
  final longest = clip.sourceDurationMs - clip.outPointMs;
  final delta = clip.sourceSpanOf(deltaMs).clamp(shortest, longest);
  return (inMs: clip.inPointMs, outMs: clip.outPointMs + delta);
}

/// Width, in logical pixels, of the band at each edge of the timeline where a
/// dragged clip or handle makes the view scroll.
const double edgeScrollZonePx = 56;

/// Fastest the view scrolls while dragging at the very edge, in pixels per
/// second.
const double edgeScrollMaxSpeed = 640;

/// How fast, in pixels per second, the view scrolls while a drag is at
/// [pointerX] of a view [viewWidth] wide: negative towards the start, zero
/// away from the edges, faster the closer to (or past) the edge.
double edgeScrollSpeed(double pointerX, double viewWidth) {
  if (viewWidth <= edgeScrollZonePx * 2) return 0;
  final double depth;
  if (pointerX < edgeScrollZonePx) {
    depth = (edgeScrollZonePx - pointerX) / edgeScrollZonePx;
  } else if (pointerX > viewWidth - edgeScrollZonePx) {
    depth = -(pointerX - (viewWidth - edgeScrollZonePx)) / edgeScrollZonePx;
  } else {
    return 0;
  }
  // Eased, so it creeps at first and runs near the edge.
  final eased = depth.abs().clamp(0.0, 1.0);
  return -depth.sign * eased * eased * edgeScrollMaxSpeed;
}

/// The room around [clip] on its [layer]: it may not start before
/// `minStartMs` nor end after `maxEndMs` (null when nothing follows it).
({int minStartMs, int? maxEndMs}) neighbourLimits(Layer layer, Clip clip) {
  var minStart = 0;
  int? maxEnd;
  for (final other in layer.clips) {
    if (other.id == clip.id) continue;
    if (other.range.endMs <= clip.startMs) {
      if (other.range.endMs > minStart) minStart = other.range.endMs;
    } else if (other.startMs >= clip.range.endMs) {
      if (maxEnd == null || other.startMs < maxEnd) maxEnd = other.startMs;
    }
  }
  return (minStartMs: minStart, maxEndMs: maxEnd);
}
