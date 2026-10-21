// All fields are final, so the class is immutable; the `meta` package that
// provides `@immutable` is not a declared dependency of the domain.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:cutter/features/editor/domain/media_asset.dart';

/// A file in a project's media bank: imported once, placed on the timeline
/// as many times as wanted.
class MediaItem {
  /// Creates the item.
  const MediaItem({
    required this.id,
    required this.path,
    required this.kind,
    required this.durationMs,
    required this.addedAtMs,
    this.projectId,
    this.width = 0,
    this.height = 0,
    this.hasAudio = false,
    this.sizeBytes = 0,
  });

  /// Unique id of the item.
  final String id;

  /// The project whose bank holds it; null once that project is gone (it
  /// stays among the recent files).
  final String? projectId;

  /// Where the file is.
  final String path;

  /// What it holds, as the engine detected it.
  final MediaKind kind;

  /// Its length; images carry the length they first show for.
  final int durationMs;

  /// Display width in pixels, 0 for sound.
  final int width;

  /// Display height in pixels, 0 for sound.
  final int height;

  /// Whether a video carries sound.
  final bool hasAudio;

  /// Size of the file in bytes.
  final int sizeBytes;

  /// When it was imported, in milliseconds since the epoch.
  final int addedAtMs;

  /// The file name without its folders.
  String get name => path.split(RegExp(r'[/\\]')).last;

  /// The asset an import places on the timeline.
  MediaAsset toAsset(String id) => MediaAsset(
        id: id,
        uri: path,
        kind: kind,
        durationMs: durationMs,
        width: width,
        height: height,
        audioPresent: hasAudio,
      );

  @override
  bool operator ==(Object other) =>
      other is MediaItem &&
      other.id == id &&
      other.projectId == projectId &&
      other.path == path &&
      other.kind == kind &&
      other.durationMs == durationMs &&
      other.width == width &&
      other.height == height &&
      other.hasAudio == hasAudio &&
      other.sizeBytes == sizeBytes &&
      other.addedAtMs == addedAtMs;

  @override
  int get hashCode => Object.hash(
        id,
        projectId,
        path,
        kind,
        durationMs,
        width,
        height,
        hasAudio,
        sizeBytes,
        addedAtMs,
      );
}

/// Storage of the media banks, owned by the domain and implemented at the
/// edge.
abstract interface class MediaBank {
  /// The bank of project [projectId], the newest first. Files deleted from
  /// the device are left out and forgotten.
  Future<List<MediaItem>> itemsOf(String projectId);

  /// Files imported into other projects, the newest first, each path once.
  Future<List<MediaItem>> recent({required String exceptProjectId, int limit});

  /// Adds [items]; a path already in the same bank is kept once.
  Future<void> add(List<MediaItem> items);

  /// Takes item [id] out of its bank; the file and the clips stay.
  Future<void> remove(String id);
}
