import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where imported files live. A file the picker left in a cache directory
/// (Android copies every pick there) is moved into the app's own storage,
/// since the system may clear caches at any time; any other file is used
/// where it is.
class MediaLibrary {
  /// Creates a library storing into [root], taking files out of
  /// [volatileRoots].
  MediaLibrary({required this.root, required this.volatileRoots});

  /// The directory imported files are kept in.
  final Directory root;

  /// Directories whose files may disappear.
  final List<String> volatileRoots;

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

  /// The lasting path of the picked file at [path].
  Future<String> keep(String path) async {
    if (!volatileRoots.any(path.startsWith)) return path;
    await root.create(recursive: true);
    final name = path.split(Platform.pathSeparator).last;
    final target = '${root.path}${Platform.pathSeparator}'
        '${DateTime.now().microsecondsSinceEpoch}_$name';
    try {
      // Same file system on Android: a rename is instant even for long
      // videos.
      return (await File(path).rename(target)).path;
    } on FileSystemException {
      return (await File(path).copy(target)).path;
    }
  }
}
