import 'package:cutter/features/editor/domain/media_asset.dart';

/// Video containers the engine (FFmpeg) plays.
const videoExtensions = {
  'mp4', 'mov', 'm4v', 'mkv', 'webm', 'avi', '3gp', 'mts', 'm2ts', 'ts', //
  'flv', 'wmv', 'mpg', 'mpeg', 'ogv',
};

/// Still image formats.
const imageExtensions = {
  'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'tif', 'tiff', 'heic', 'heif', //
  'avif',
};

/// Sound formats.
const audioExtensions = {
  'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'oga', 'opus', 'wma', 'aiff', //
  'aif', 'amr',
};

/// Every extension the import offers.
final Set<String> mediaExtensions = {
  ...videoExtensions,
  ...imageExtensions,
  ...audioExtensions,
};

/// The extension of [path], lower case, without the dot.
String extensionOf(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// What a file probably holds, from its name; the engine has the last word
/// when it is imported. Null for files the import does not offer.
MediaKind? kindByName(String path) {
  final ext = extensionOf(path);
  if (videoExtensions.contains(ext)) return MediaKind.video;
  if (imageExtensions.contains(ext)) return MediaKind.image;
  if (audioExtensions.contains(ext)) return MediaKind.audio;
  return null;
}
