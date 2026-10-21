// All fields are final, so the class is immutable; the `meta` package that
// provides `@immutable` is not a declared dependency of the domain.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/time_range.dart';

/// The shortest duration a clip may have, in milliseconds.
const minClipDurationMs = 100;

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

  /// Duration of the played part of the source.
  int get durationMs => outPointMs - inPointMs;

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
    String? id,
  }) {
    return Clip(
      id: id ?? this.id,
      layerId: layerId ?? this.layerId,
      assetId: assetId,
      sourceUri: sourceUri,
      kind: kind,
      startMs: startMs ?? this.startMs,
      inPointMs: inPointMs ?? this.inPointMs,
      outPointMs: outPointMs ?? this.outPointMs,
      sourceDurationMs: sourceDurationMs,
      reversed: reversed ?? this.reversed,
      volume: volume ?? this.volume,
      filterId: clearFilter ? null : (filterId ?? this.filterId),
      adjustments: adjustments ?? this.adjustments,
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
        Object.hashAllUnordered(
          adjustments.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );

  @override
  String toString() =>
      'Clip($id, layer $layerId, start $startMs, '
      'in $inPointMs, out $outPointMs)';
}
