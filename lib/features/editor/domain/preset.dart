/// A named set of captured clip settings that can be applied to other clips.
library;

import 'package:flutter/foundation.dart' show immutable, mapEquals;

/// A preset captures the filter, adjustments and volume of a configured clip.
@immutable
class Preset {
  /// Creates an immutable preset.
  const Preset({
    required this.id,
    required this.name,
    this.filterId,
    this.adjustments = const {},
    this.volume = 1.0,
  });

  /// Unique identifier of the preset.
  final String id;

  /// Display name chosen by the user.
  final String name;

  /// The captured filter, or null when the clip had none.
  final String? filterId;

  /// The captured adjustment values by key.
  final Map<String, double> adjustments;

  /// The captured clip volume in [0.0, 1.0].
  final double volume;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Preset &&
          other.id == id &&
          other.name == name &&
          other.filterId == filterId &&
          other.volume == volume &&
          mapEquals(other.adjustments, adjustments);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        filterId,
        volume,
        Object.hashAllUnordered(
          adjustments.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );

  @override
  String toString() =>
      'Preset($id, $name, filter: $filterId, adjustments: $adjustments, '
      'volume: $volume)';
}
