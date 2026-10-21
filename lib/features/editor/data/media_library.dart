import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The device has no room to keep a copy of an imported file.
class MediaStorageFull implements Exception {
  /// Creates the error for the file at [path].
  const MediaStorageFull(this.path);

  /// The file that could not be copied.
  final String path;

  @override
  String toString() => 'Not enough storage to keep $path';
}

/// An imported file could not be copied into the app.
class MediaCopyFailed implements Exception {
  /// Creates the error for the file at [path], caused by [cause].
  const MediaCopyFailed(this.path, this.cause);

  /// The file that could not be copied.
  final String path;

  /// What went wrong.
  final Object cause;

  @override
  String toString() => 'Could not keep $path: $cause';
}

/// Copies [from] to [to]; replaced in tests.
typedef FileCopier = Future<void> Function(String from, String to);

// errno of "no space left on device" on Linux and Android.
const int _noSpaceErrno = 28;

Future<void> _copyFile(String from, String to) async {
  await File(from).copy(to);
}

/// Where imported and recorded files live. Every file is kept in the app's
/// own storage, so a file the user moves, renames or deletes afterwards
/// cannot break a project. A file the picker left in a cache directory
/// (Android copies every pick there) is moved, since the system may clear
/// caches at any time and a second copy would only waste space; any other
/// file is copied and the original is left alone.
class MediaLibrary {
  /// Creates a library storing into [root], moving files out of
  /// [volatileRoots].
  MediaLibrary({
    required this.root,
    required this.volatileRoots,
    FileCopier copier = _copyFile,
  }) : _copy = copier;

  /// The directory imported files are kept in.
  final Directory root;

  /// Directories whose files may disappear.
  final List<String> volatileRoots;

  final FileCopier _copy;

  /// The library in the app-support directory, rescuing files from the
  /// temporary directory.
  static Future<MediaLibrary> open() async {
    final support = await getApplicationSupportDirectory();
    final temporary = await getTemporaryDirectory();
    return MediaLibrary(
      root: Directory('${support.path}${Platform.pathSeparator}media'),
      volatileRoots: [temporary.path],
    );
  }

  /// Whether [path] is already one of the library's files.
  bool contains(String path) =>
      path.startsWith('${root.path}${Platform.pathSeparator}');

  /// The lasting path of the picked file at [path].
  ///
  /// Throws [MediaStorageFull] when the device has no room for the copy and
  /// [MediaCopyFailed] for any other failure; a half-written copy is
  /// removed.
  Future<String> keep(String path) async {
    if (contains(path)) return path;
    await root.create(recursive: true);
    final name = path.split(Platform.pathSeparator).last;
    final target = '${root.path}${Platform.pathSeparator}'
        '${DateTime.now().microsecondsSinceEpoch}_$name';
    try {
      if (volatileRoots.any(path.startsWith)) {
        try {
          // Same file system on Android: a rename is instant even for long
          // videos.
          await File(path).rename(target);
          return target;
        } on FileSystemException {
          // Another file system: fall through to a copy.
        }
      }
      await _copy(path, target);
      return target;
    } on FileSystemException catch (error) {
      await _discard(target);
      if (error.osError?.errorCode == _noSpaceErrno) {
        throw MediaStorageFull(path);
      }
      throw MediaCopyFailed(path, error);
    }
  }

  Future<void> _discard(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Nothing more can be done about a leftover.
    }
  }
}
