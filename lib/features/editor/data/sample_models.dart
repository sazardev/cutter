// Sample domain models used by the editor screens until the real
// domain exists.

/// The kind of media a layer or clip holds.
enum LayerKind {
  /// Moving pictures, possibly with sound.
  video,

  /// A still image.
  image,

  /// Sound only.
  audio,
}

/// A clip placed on a layer. Times are integer milliseconds.
class SampleClip {
  /// Creates a clip.
  const SampleClip({
    required this.id,
    required this.name,
    required this.kind,
    required this.startMs,
    required this.durationMs,
    required this.inMs,
    required this.outMs,
    this.reversed = false,
    this.volume = 1.0,
    this.filterId,
    this.adjustments = const <String, double>{},
  });

  /// Unique id of the clip.
  final String id;

  /// File name shown to the user.
  final String name;

  /// Kind of media the clip holds.
  final LayerKind kind;

  /// Start position on the timeline in milliseconds.
  final int startMs;

  /// Length on the timeline in milliseconds.
  final int durationMs;

  /// In point inside the source media in milliseconds.
  final int inMs;

  /// Out point inside the source media in milliseconds.
  final int outMs;

  /// Whether the clip plays backwards.
  final bool reversed;

  /// Clip volume from 0 to 1.
  final double volume;

  /// Id of the applied filter, or null when none is applied.
  final String? filterId;

  /// Adjustment values by key.
  final Map<String, double> adjustments;

  /// End position on the timeline in milliseconds.
  int get endMs => startMs + durationMs;

  /// Returns a copy with the given fields replaced.
  ///
  /// Pass [clearFilter] to remove the filter.
  SampleClip copyWith({
    String? id,
    String? name,
    LayerKind? kind,
    int? startMs,
    int? durationMs,
    int? inMs,
    int? outMs,
    bool? reversed,
    double? volume,
    String? filterId,
    bool clearFilter = false,
    Map<String, double>? adjustments,
  }) {
    return SampleClip(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      startMs: startMs ?? this.startMs,
      durationMs: durationMs ?? this.durationMs,
      inMs: inMs ?? this.inMs,
      outMs: outMs ?? this.outMs,
      reversed: reversed ?? this.reversed,
      volume: volume ?? this.volume,
      filterId: clearFilter ? null : (filterId ?? this.filterId),
      adjustments: adjustments ?? this.adjustments,
    );
  }
}

/// A timeline layer holding clips of one kind.
class SampleLayer {
  /// Creates a layer.
  const SampleLayer({
    required this.id,
    required this.kind,
    required this.name,
    this.volume = 1.0,
    this.muted = false,
    this.clips = const <SampleClip>[],
  });

  /// Unique id of the layer.
  final String id;

  /// Kind of media the layer holds.
  final LayerKind kind;

  /// Name shown to the user.
  final String name;

  /// Layer volume from 0 to 1.
  final double volume;

  /// Whether the layer is silenced.
  final bool muted;

  /// Clips on the layer.
  final List<SampleClip> clips;

  /// Returns a copy with the given fields replaced.
  SampleLayer copyWith({
    String? id,
    LayerKind? kind,
    String? name,
    double? volume,
    bool? muted,
    List<SampleClip>? clips,
  }) {
    return SampleLayer(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      clips: clips ?? this.clips,
    );
  }
}

/// A project: ordered layers on a single millisecond timebase.
class SampleProject {
  /// Creates a project.
  const SampleProject({
    required this.id,
    required this.name,
    required this.layers,
  });

  /// Unique id of the project.
  final String id;

  /// Name shown to the user.
  final String name;

  /// Layers in timeline order.
  final List<SampleLayer> layers;

  /// The latest clip end across all layers, or 0 when the project is empty.
  int get durationMs {
    var longest = 0;
    for (final layer in layers) {
      for (final clip in layer.clips) {
        if (clip.endMs > longest) longest = clip.endMs;
      }
    }
    return longest;
  }

  /// Returns a copy with the given fields replaced.
  SampleProject copyWith({
    String? id,
    String? name,
    List<SampleLayer>? layers,
  }) {
    return SampleProject(
      id: id ?? this.id,
      name: name ?? this.name,
      layers: layers ?? this.layers,
    );
  }
}

/// A media item offered by the media picker.
class SampleAsset {
  /// Creates an asset.
  const SampleAsset({
    required this.id,
    required this.name,
    required this.kind,
    required this.durationMs,
    required this.supported,
  });

  /// Unique id of the asset.
  final String id;

  /// File name shown to the user.
  final String name;

  /// Kind of media the asset holds.
  final LayerKind kind;

  /// Intrinsic duration in milliseconds.
  final int durationMs;

  /// Whether the file can be imported.
  final bool supported;
}

/// A visual filter that can be applied to a clip.
class SampleFilter {
  /// Creates a filter.
  const SampleFilter({required this.id, required this.name});

  /// Unique id of the filter.
  final String id;

  /// Name shown to the user.
  final String name;
}

/// A saved set of clip settings.
class SamplePreset {
  /// Creates a preset.
  const SamplePreset({
    required this.id,
    required this.name,
    this.filterId,
    this.adjustments = const <String, double>{},
    this.volume = 1.0,
  });

  /// Unique id of the preset.
  final String id;

  /// Name shown to the user.
  final String name;

  /// Id of the captured filter, or null when none.
  final String? filterId;

  /// Captured adjustment values by key.
  final Map<String, double> adjustments;

  /// Captured clip volume from 0 to 1.
  final double volume;
}

/// A media slot a template expects to be filled.
class SampleSlot {
  /// Creates a slot.
  const SampleSlot({required this.id, required this.kind});

  /// Unique id of the slot.
  final String id;

  /// Kind of media the slot expects.
  final LayerKind kind;
}

/// A template that creates a project once its slots are filled.
class SampleTemplate {
  /// Creates a template.
  const SampleTemplate({
    required this.id,
    required this.name,
    required this.slots,
  });

  /// Unique id of the template.
  final String id;

  /// Name shown to the user.
  final String name;

  /// Media slots to fill before the project is created.
  final List<SampleSlot> slots;
}
