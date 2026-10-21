import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/domain/time_range.dart';

/// How long a still image plays when it is first placed.
const defaultImageDurationMs = 3000;

/// How far an image clip may be stretched: a still has no end of its own.
const maxImageDurationMs = 10 * 60 * 1000;

/// Describes media files so they can be imported; implemented by the engine.
// ignore: one_member_abstracts
abstract interface class MediaInspector {
  /// Describes the file at [path]. A file the engine cannot play comes back
  /// with `supported` false; images come back with
  /// [defaultImageDurationMs].
  Future<MediaAsset> inspect(String path);

  /// The display width and height of the picture at [path], or null when
  /// it cannot be read. Nothing is copied.
  Future<(int, int)?> measure(String path);
}

/// Where imported media lands on the timeline.
enum ImportPlacement {
  /// Pictures go to the end of the main sequence, one after another; sound
  /// goes to the playhead.
  append,

  /// Everything goes to the playhead on a new layer in front of the others.
  overlay,
}

/// Places imported media files on the timeline as new clips, creating the
/// layers they need. The whole import is rejected when one file is
/// unsupported, so the caller lists rejected files before importing.
class ImportMedia {
  /// Creates the use case over the given project storage and id source.
  ImportMedia(this._projects, this._ids);

  final ProjectRepository _projects;
  final IdGenerator _ids;

  /// Imports [assets] into project [projectId]; [atMs] is the playhead.
  Future<EditorResult<Project>> call({
    required String projectId,
    required List<MediaAsset> assets,
    required int atMs,
    ImportPlacement placement = ImportPlacement.append,
  }) async {
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    if (assets.any((a) => !a.supported)) return const Err(UnsupportedMedia());
    if (atMs < 0) return const Err(NegativeStart());
    if (assets.any((a) => a.durationMs < minClipDurationMs)) {
      return const Err(ZeroDuration());
    }

    var layers = List<Layer>.of(project.layers);
    var visualCursor = _sequenceEnd(layers);
    final overlayLayers = <MediaKind, String>{};
    var overlayCursor = atMs;

    for (final asset in assets) {
      final duration = asset.durationMs;
      final String layerId;
      final int start;
      if (placement == ImportPlacement.overlay) {
        start = overlayCursor;
        overlayCursor += duration;
        final existing = overlayLayers[asset.kind];
        if (existing != null) {
          layerId = existing;
        } else {
          final layer = Layer(id: _ids.next(), name: '', kind: asset.kind);
          layers = asset.kind == MediaKind.audio
              ? [...layers, layer]
              : [layer, ...layers];
          overlayLayers[asset.kind] = layer.id;
          layerId = layer.id;
        }
      } else if (asset.kind == MediaKind.audio) {
        start = atMs;
        final range = TimeRange(start, duration);
        final free = layers.where(
          (l) =>
              l.kind == MediaKind.audio &&
              !l.clips.any((c) => c.range.overlaps(range)),
        );
        if (free.isNotEmpty) {
          layerId = free.first.id;
        } else {
          final layer = Layer(id: _ids.next(), name: '', kind: asset.kind);
          layers = [...layers, layer];
          layerId = layer.id;
        }
      } else {
        start = visualCursor;
        visualCursor += duration;
        final main = layers.lastWhere(
          (l) => l.kind == asset.kind,
          orElse: () => Layer(id: '', name: '', kind: asset.kind),
        );
        if (main.id.isNotEmpty) {
          layerId = main.id;
        } else {
          final layer = Layer(id: _ids.next(), name: '', kind: asset.kind);
          layers = _insertBehindVisuals(layers, layer);
          layerId = layer.id;
        }
      }

      final clip = Clip(
        id: _ids.next(),
        layerId: layerId,
        assetId: asset.id,
        sourceUri: asset.uri,
        kind: asset.kind,
        startMs: start,
        inPointMs: 0,
        outPointMs: duration,
        sourceDurationMs:
            asset.kind == MediaKind.image ? maxImageDurationMs : duration,
        sourceWidth: asset.width,
        sourceHeight: asset.height,
      );
      layers = [
        for (final layer in layers)
          if (layer.id == layerId)
            layer.withClips([...layer.clips, clip])
          else
            layer,
      ];
    }

    final updated = project.withLayers(layers);
    await _projects.save(updated);
    return Ok(updated);
  }

  /// The end of the last picture on any video or image layer.
  static int _sequenceEnd(List<Layer> layers) {
    var end = 0;
    for (final layer in layers) {
      if (layer.kind == MediaKind.audio) continue;
      for (final clip in layer.clips) {
        if (clip.range.endMs > end) end = clip.range.endMs;
      }
    }
    return end;
  }

  /// A new main layer goes behind the existing pictures, in front of sound.
  static List<Layer> _insertBehindVisuals(List<Layer> layers, Layer layer) {
    final firstAudio = layers.indexWhere((l) => l.kind == MediaKind.audio);
    if (firstAudio < 0) return [...layers, layer];
    return [...layers]..insert(firstAudio, layer);
  }
}
