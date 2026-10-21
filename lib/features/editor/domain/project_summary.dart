// All fields are final, so the class is immutable; the `meta` package that
// provides `@immutable` is not a declared dependency of the domain.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// What the home screen shows about a stored project, without its clips.
class ProjectSummary {
  /// Creates the summary of one project.
  const ProjectSummary({
    required this.id,
    required this.name,
    required this.layerCount,
    required this.clipCount,
    required this.durationMs,
    required this.updatedAtMs,
    this.savedAtMs,
    this.coverUri,
    this.coverMs = 0,
  });

  /// Unique id of the project.
  final String id;

  /// Display name of the project.
  final String name;

  /// How many layers the project has.
  final int layerCount;

  /// How many clips the project has across all layers.
  final int clipCount;

  /// The largest clip end across all layers, 0 when there are no clips.
  final int durationMs;

  /// When the project last changed, in milliseconds since the epoch. Every
  /// edit is stored at once.
  final int updatedAtMs;

  /// When the last restore point was saved, or null when there is none.
  final int? savedAtMs;

  /// The source of the first picture or video clip of the project, whose
  /// frame stands for the project in lists; null when there is none.
  final String? coverUri;

  /// The moment of [coverUri] to show, in milliseconds of the source.
  final int coverMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectSummary &&
          other.id == id &&
          other.name == name &&
          other.layerCount == layerCount &&
          other.clipCount == clipCount &&
          other.durationMs == durationMs &&
          other.updatedAtMs == updatedAtMs &&
          other.savedAtMs == savedAtMs &&
          other.coverUri == coverUri &&
          other.coverMs == coverMs;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        layerCount,
        clipCount,
        durationMs,
        updatedAtMs,
        savedAtMs,
        coverUri,
        coverMs,
      );
}
