// All fields are final, so the class is immutable; the `meta` package that
// provides `@immutable` is not a declared dependency of the domain.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';

/// A timeline layer holding clips of a single [MediaKind]. Clips are always
/// kept sorted by their start time.
class Layer {
  /// Creates a layer; [clips] are copied and sorted by start time.
  Layer({
    required this.id,
    required this.name,
    required this.kind,
    this.volume = 1,
    this.muted = false,
    List<Clip> clips = const [],
  }) : clips = List.unmodifiable(_sortedByStart(clips));

  /// Unique id of the layer.
  final String id;

  /// Display name of the layer.
  final String name;

  /// The kind of media the layer holds.
  final MediaKind kind;

  /// Layer volume in the range 0.0 to 1.0.
  final double volume;

  /// Whether the layer is silent.
  final bool muted;

  /// The clips of the layer, sorted by start time.
  final List<Clip> clips;

  /// The volume a clip is heard at: silent when the layer is muted, otherwise
  /// the layer volume combined with the clip volume.
  double effectiveVolumeOf(Clip clip) {
    if (muted) return 0;
    return volume * clip.volume;
  }

  /// Returns a copy holding [newClips], sorted by start time.
  Layer withClips(List<Clip> newClips) => copyWith(clips: newClips);

  /// Returns a modified copy.
  Layer copyWith({
    double? volume,
    bool? muted,
    List<Clip>? clips,
  }) {
    return Layer(
      id: id,
      name: name,
      kind: kind,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      clips: clips ?? this.clips,
    );
  }

  static List<Clip> _sortedByStart(List<Clip> clips) {
    return List<Clip>.of(clips)..sort((a, b) => a.startMs.compareTo(b.startMs));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Layer &&
          other.id == id &&
          other.name == name &&
          other.kind == kind &&
          other.volume == volume &&
          other.muted == muted &&
          _sameClips(other.clips);

  bool _sameClips(List<Clip> other) {
    if (other.length != clips.length) return false;
    for (var i = 0; i < clips.length; i++) {
      if (other[i] != clips[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        kind,
        volume,
        muted,
        Object.hashAll(clips),
      );

  @override
  String toString() => 'Layer($id, $name, ${clips.length} clips)';
}
