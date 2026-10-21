import 'dart:io';

import 'package:cutter/features/storage/domain/storage_report.dart';

/// What the scanner needs to know about a project: its name and the paths of
/// the files its clips use.
class ProjectMedia {
  /// Creates the description.
  const ProjectMedia({
    required this.id,
    required this.name,
    required this.paths,
    this.trashed = false,
  });

  /// Id of the project.
  final String id;

  /// Name of the project.
  final String name;

  /// Paths of the files the project's clips use.
  final Set<String> paths;

  /// Whether the project is in the trash.
  final bool trashed;
}

/// Files younger than this are never cleaned from the cache: a picked file
/// may be waiting there to be imported, or a recording to be saved.
const Duration cacheMinAge = Duration(hours: 1);

/// Every file under [dir] with its size; a missing folder has none.
Map<String, int> _filesUnder(Directory dir) {
  final files = <String, int>{};
  if (!dir.existsSync()) return files;
  try {
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          files[entity.path] = entity.lengthSync();
        } on FileSystemException {
          // A file that vanished while scanning is not there to count.
        }
      }
    }
  } on FileSystemException {
    // An unreadable folder counts as empty.
  }
  return files;
}

/// Measures what Cutter keeps: the media folder (and which of it nothing
/// uses, and how much each project accounts for), the rendered videos and
/// the cache.
///
/// Only the app's own folders are ever read or cleaned. [exportBytes] comes
/// from the export records, so the scan never walks the user's own folders.
StorageReport scanStorage({
  required Directory mediaRoot,
  required Directory cacheDir,
  required List<ProjectMedia> projects,
  required int exportBytes,
}) {
  final media = _filesUnder(mediaRoot);
  final cache = _filesUnder(cacheDir);

  final users = <String, int>{};
  for (final project in projects) {
    for (final path in project.paths) {
      users[path] = (users[path] ?? 0) + 1;
    }
  }

  final unused = [
    for (final path in media.keys)
      if (!users.containsKey(path)) path,
  ]..sort();

  final perProject = <ProjectStorage>[];
  for (final project in projects) {
    var bytes = 0;
    var shared = 0;
    for (final path in project.paths) {
      final size = media[path];
      if (size == null) continue;
      bytes += size;
      if ((users[path] ?? 0) > 1) shared += size;
    }
    perProject.add(
      ProjectStorage(
        id: project.id,
        name: project.name,
        bytes: bytes,
        sharedBytes: shared,
        trashed: project.trashed,
      ),
    );
  }
  perProject.sort((a, b) => b.bytes.compareTo(a.bytes));

  return StorageReport(
    mediaBytes: media.values.fold(0, (sum, size) => sum + size),
    unusedPaths: unused,
    unusedBytes: unused.fold(0, (sum, path) => sum + media[path]!),
    exportBytes: exportBytes,
    cacheBytes: cache.values.fold(0, (sum, size) => sum + size),
    projects: perProject,
  );
}

/// Deletes the cache files not touched in the last [minAge] and returns the
/// bytes freed. Folders are left in place.
int clearCache(
  Directory cacheDir, {
  Duration minAge = cacheMinAge,
  DateTime? now,
}) {
  final limit = (now ?? DateTime.now()).subtract(minAge);
  var freed = 0;
  for (final path in _filesUnder(cacheDir).keys) {
    final file = File(path);
    try {
      if (file.lastModifiedSync().isAfter(limit)) continue;
      final size = file.lengthSync();
      file.deleteSync();
      freed += size;
    } on FileSystemException {
      // A file that cannot be removed stays and is not counted.
    }
  }
  return freed;
}

/// Deletes the files at [paths], but only those inside [mediaRoot], and
/// returns the bytes freed. A path outside the folder is never touched, so a
/// wrong list cannot remove the user's own files.
int deleteMediaFiles(Directory mediaRoot, Iterable<String> paths) {
  final prefix = '${mediaRoot.path}${Platform.pathSeparator}';
  var freed = 0;
  for (final path in paths) {
    if (!path.startsWith(prefix)) continue;
    final file = File(path);
    try {
      if (!file.existsSync()) continue;
      final size = file.lengthSync();
      file.deleteSync();
      freed += size;
    } on FileSystemException {
      // Stays, uncounted.
    }
  }
  return freed;
}
