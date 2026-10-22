// All fields are final, so the class is immutable; the `meta` package that
// provides `@immutable` is not a declared dependency of the domain.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:cutter/features/editor/domain/clip_crop.dart';
import 'package:cutter/features/editor/domain/clip_drawing.dart';
import 'package:cutter/features/editor/domain/clip_text.dart';
import 'package:cutter/features/editor/domain/clip_transform.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/time_range.dart';

/// The shortest duration a clip may have, in milliseconds: one frame at 30
/// fps, so short sound effects (a click, a whoosh) can be used whole.
const minClipDurationMs = 33;

/// The ids of the animations a clip comes in and goes out with, in the order
/// the editor lists them. The engine renders the same ids.
const clipAnimationIds = [
  'fade',
  'slide_left',
  'slide_right',
  'slide_up',
  'slide_down',
  'zoom_in',
  'zoom_out',
  'spin',
  'pop',
];

/// Longest an entrance or an exit may last, in milliseconds.
const maxClipAnimationMs = 3000;

/// Slowest playback speed of a clip.
const minClipSpeed = 0.25;

/// Fastest playback speed of a clip.
const maxClipSpeed = 4.0;

/// A clip placed on a layer, playing the part of its source between
/// [inPointMs] and [outPointMs]. All times are integer milliseconds.
class Clip {
  /// Creates a clip.
  const Clip({
    required this.id,
    required this.layerId,
    required this.assetId,
    required this.sourceUri,
    required this.kind,
    required this.startMs,
    required this.inPointMs,
    required this.outPointMs,
    required this.sourceDurationMs,
    this.reversed = false,
    this.volume = 1.0,
    this.filterId,
    this.adjustments = const {},
    this.transform = const ClipTransform(),
    this.sourceWidth = 0,
    this.sourceHeight = 0,
    this.crop = const ClipCrop(),
    this.speed = 1,
    this.fadeInMs = 0,
    this.fadeOutMs = 0,
    this.text,
    this.animIn,
    this.animInMs = 0,
    this.animOut,
    this.animOutMs = 0,
    this.drawing,
  });

  /// Unique id of the clip.
  final String id;

  /// Id of the layer holding the clip.
  final String layerId;

  /// Id of the media asset the clip plays.
  final String assetId;

  /// Location of the source media.
  final String sourceUri;

  /// The kind of media the clip holds.
  final MediaKind kind;

  /// Position of the clip on the project timeline.
  final int startMs;

  /// Start of the played part of the source.
  final int inPointMs;

  /// End of the played part of the source.
  final int outPointMs;

  /// Full duration of the source media.
  final int sourceDurationMs;

  /// Whether the clip plays backwards.
  final bool reversed;

  /// Clip volume in the range 0.0 to 1.0.
  final double volume;

  /// Id of the applied filter, or null when none is applied.
  final String? filterId;

  /// Adjustment values by key.
  final Map<String, double> adjustments;

  /// Where and how the picture sits on the canvas; ignored for sound.
  final ClipTransform transform;

  /// Display width of the source in pixels, 0 when unknown or for sound.
  final int sourceWidth;

  /// Display height of the source in pixels, 0 when unknown or for sound.
  final int sourceHeight;

  /// The part of the source picture kept.
  final ClipCrop crop;

  /// Playback speed: 2 plays twice as fast and lasts half as long.
  final double speed;

  /// Length of the sound fade at the start, in timeline milliseconds.
  final int fadeInMs;

  /// Length of the sound fade at the end, in timeline milliseconds.
  final int fadeOutMs;

  /// The words and look of a text clip; null for any other clip.
  final ClipText? text;

  /// Id of the animation the clip comes in with (see [clipAnimationIds]), or
  /// null when it just appears.
  final String? animIn;

  /// How long the entrance lasts, in timeline milliseconds.
  final int animInMs;

  /// Id of the animation the clip goes out with, or null when it just
  /// disappears.
  final String? animOut;

  /// How long the exit lasts, in timeline milliseconds.
  final int animOutMs;

  /// The strokes of a drawing clip, kept so it can be edited again; null for
  /// any other clip. The clip's picture is the rendered PNG at [sourceUri].
  final ClipDrawing? drawing;

  /// How long the clip lasts on the timeline: its source span at its
  /// speed.
  int get durationMs => ((outPointMs - inPointMs) / speed).round();

  /// The source milliseconds played during [timelineMs] of the clip.
  int sourceSpanOf(int timelineMs) => (timelineMs * speed).round();

  /// The span the clip occupies on the timeline.
  TimeRange get range => TimeRange(startMs, durationMs);

  /// Returns a modified copy. Pass [clearFilter] to remove the filter, since
  /// a null [filterId] means "keep the current one".
  Clip copyWith({
    String? layerId,
    int? startMs,
    int? inPointMs,
    int? outPointMs,
    bool? reversed,
    double? volume,
    String? filterId,
    bool clearFilter = false,
    Map<String, double>? adjustments,
    ClipTransform? transform,
    int? sourceWidth,
    int? sourceHeight,
    ClipCrop? crop,
    double? speed,
    int? fadeInMs,
    int? fadeOutMs,
    String? id,
    String? sourceUri,
    String? assetId,
    ClipText? text,
    String? animIn,
    bool clearAnimIn = false,
    int? animInMs,
    String? animOut,
    bool clearAnimOut = false,
    int? animOutMs,
    ClipDrawing? drawing,
  }) {
    return Clip(
      id: id ?? this.id,
      layerId: layerId ?? this.layerId,
      assetId: assetId ?? this.assetId,
      sourceUri: sourceUri ?? this.sourceUri,
      kind: kind,
      startMs: startMs ?? this.startMs,
      inPointMs: inPointMs ?? this.inPointMs,
      outPointMs: outPointMs ?? this.outPointMs,
      sourceDurationMs: sourceDurationMs,
      reversed: reversed ?? this.reversed,
      volume: volume ?? this.volume,
      filterId: clearFilter ? null : (filterId ?? this.filterId),
      adjustments: adjustments ?? this.adjustments,
      transform: transform ?? this.transform,
      sourceWidth: sourceWidth ?? this.sourceWidth,
      sourceHeight: sourceHeight ?? this.sourceHeight,
      crop: crop ?? this.crop,
      speed: speed ?? this.speed,
      fadeInMs: fadeInMs ?? this.fadeInMs,
      fadeOutMs: fadeOutMs ?? this.fadeOutMs,
      text: text ?? this.text,
      animIn: clearAnimIn ? null : (animIn ?? this.animIn),
      animInMs: animInMs ?? this.animInMs,
      animOut: clearAnimOut ? null : (animOut ?? this.animOut),
      animOutMs: animOutMs ?? this.animOutMs,
      drawing: drawing ?? this.drawing,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Clip &&
          other.id == id &&
          other.layerId == layerId &&
          other.assetId == assetId &&
          other.sourceUri == sourceUri &&
          other.kind == kind &&
          other.startMs == startMs &&
          other.inPointMs == inPointMs &&
          other.outPointMs == outPointMs &&
          other.sourceDurationMs == sourceDurationMs &&
          other.reversed == reversed &&
          other.volume == volume &&
          other.filterId == filterId &&
          other.transform == transform &&
          other.sourceWidth == sourceWidth &&
          other.sourceHeight == sourceHeight &&
          other.crop == crop &&
          other.speed == speed &&
          other.fadeInMs == fadeInMs &&
          other.fadeOutMs == fadeOutMs &&
          other.text == text &&
          other.animIn == animIn &&
          other.animInMs == animInMs &&
          other.animOut == animOut &&
          other.animOutMs == animOutMs &&
          other.drawing == drawing &&
          _sameAdjustments(other.adjustments);

  bool _sameAdjustments(Map<String, double> other) {
    if (other.length != adjustments.length) return false;
    for (final entry in adjustments.entries) {
      if (other[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        id,
        layerId,
        assetId,
        sourceUri,
        kind,
        startMs,
        inPointMs,
        outPointMs,
        sourceDurationMs,
        reversed,
        volume,
        filterId,
        transform,
        sourceWidth,
        sourceHeight,
        Object.hash(crop, speed, fadeInMs, fadeOutMs, text),
        Object.hash(animIn, animInMs, animOut, animOutMs, drawing),
        Object.hashAllUnordered(
          adjustments.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );

  @override
  String toString() => 'Clip($id, layer $layerId, start $startMs, '
      'in $inPointMs, out $outPointMs)';
}
