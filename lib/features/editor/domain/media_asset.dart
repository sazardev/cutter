// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// The kinds of media a layer or clip can hold.
enum MediaKind {
  /// A video file, with or without an audio track.
  video,

  /// A still image.
  image,

  /// An audio file.
  audio,
}

/// An imported media file as the engine described it.
///
/// For images, [durationMs] is the intrinsic duration chosen by the import
/// adapter; the domain does not pick a default.
class MediaAsset {
  /// Creates a media asset description.
  const MediaAsset({
    required this.id,
    required this.uri,
    required this.kind,
    required this.durationMs,
    this.width = 0,
    this.height = 0,
    this.audioPresent = false,
    this.supported = true,
  });

  /// Unique id of the asset.
  final String id;

  /// Location of the source file on the device.
  final String uri;

  /// What kind of media the file holds.
  final MediaKind kind;

  /// Intrinsic duration in milliseconds.
  final int durationMs;

  /// Width in pixels, 0 when not applicable.
  final int width;

  /// Height in pixels, 0 when not applicable.
  final int height;

  /// Whether the file contains an audio track.
  final bool audioPresent;

  /// False when the file is in an unsupported format or is corrupt.
  final bool supported;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaAsset &&
          other.id == id &&
          other.uri == uri &&
          other.kind == kind &&
          other.durationMs == durationMs &&
          other.width == width &&
          other.height == height &&
          other.audioPresent == audioPresent &&
          other.supported == supported;

  @override
  int get hashCode => Object.hash(
        id,
        uri,
        kind,
        durationMs,
        width,
        height,
        audioPresent,
        supported,
      );
}
