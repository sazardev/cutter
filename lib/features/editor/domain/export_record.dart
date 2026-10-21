// All fields are final, so the class is immutable; the `meta` package that
// provides `@immutable` is not a declared dependency of the domain.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// A finished video the app rendered, for the "Your videos" library.
class ExportRecord {
  /// Creates the record.
  const ExportRecord({
    required this.id,
    required this.path,
    required this.projectName,
    required this.width,
    required this.height,
    required this.fps,
    required this.durationMs,
    required this.sizeBytes,
    required this.createdAtMs,
    required this.preset,
    this.projectId,
    this.inGallery = false,
  });

  /// Unique id of the record.
  final String id;

  /// Where the file is.
  final String path;

  /// The project it came from, or null when that project was deleted.
  final String? projectId;

  /// The name of the project when it was rendered.
  final String projectName;

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// Frames per second.
  final int fps;

  /// Length in milliseconds.
  final int durationMs;

  /// Size of the file in bytes.
  final int sizeBytes;

  /// When it was rendered, in milliseconds since the epoch.
  final int createdAtMs;

  /// The id of the export preset used.
  final String preset;

  /// Whether it was copied into the device gallery.
  final bool inGallery;

  @override
  bool operator ==(Object other) =>
      other is ExportRecord &&
      other.id == id &&
      other.path == path &&
      other.projectId == projectId &&
      other.projectName == projectName &&
      other.width == width &&
      other.height == height &&
      other.fps == fps &&
      other.durationMs == durationMs &&
      other.sizeBytes == sizeBytes &&
      other.createdAtMs == createdAtMs &&
      other.preset == preset &&
      other.inGallery == inGallery;

  @override
  int get hashCode => Object.hash(
        id,
        path,
        projectId,
        projectName,
        width,
        height,
        fps,
        durationMs,
        sizeBytes,
        createdAtMs,
        preset,
        inGallery,
      );
}

/// Storage of the rendered videos, owned by the domain and implemented at
/// the edge.
abstract interface class ExportLibrary {
  /// Remembers a finished video.
  Future<void> add(ExportRecord record);

  /// Every remembered video whose file still exists, the newest first; the
  /// records of files deleted outside the app are forgotten.
  Future<List<ExportRecord>> all();

  /// Forgets a video and deletes its file.
  Future<void> remove(String id);
}
