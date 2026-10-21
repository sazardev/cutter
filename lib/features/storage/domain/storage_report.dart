/// How much disk one project's media takes.
class ProjectStorage {
  /// Creates the entry for a project.
  const ProjectStorage({
    required this.id,
    required this.name,
    required this.bytes,
    required this.sharedBytes,
    required this.trashed,
  });

  /// Id of the project.
  final String id;

  /// Name of the project.
  final String name;

  /// Bytes of the app's media files its clips use.
  final int bytes;

  /// How many of those bytes belong to files other projects use as well.
  final int sharedBytes;

  /// Whether the project is in the trash.
  final bool trashed;
}

/// What Cutter keeps on the device and what could be cleaned.
class StorageReport {
  /// Creates a report.
  const StorageReport({
    required this.mediaBytes,
    required this.unusedPaths,
    required this.unusedBytes,
    required this.exportBytes,
    required this.cacheBytes,
    required this.projects,
  });

  /// An empty report.
  static const empty = StorageReport(
    mediaBytes: 0,
    unusedPaths: [],
    unusedBytes: 0,
    exportBytes: 0,
    cacheBytes: 0,
    projects: [],
  );

  /// Bytes of every file in the app's media folder.
  final int mediaBytes;

  /// The media files no clip of any project uses.
  final List<String> unusedPaths;

  /// Bytes of [unusedPaths].
  final int unusedBytes;

  /// Bytes of the rendered videos.
  final int exportBytes;

  /// Bytes of temporary files Cutter can recreate.
  final int cacheBytes;

  /// The projects, the biggest first.
  final List<ProjectStorage> projects;

  /// Everything Cutter holds.
  int get totalBytes => mediaBytes + exportBytes + cacheBytes;
}
