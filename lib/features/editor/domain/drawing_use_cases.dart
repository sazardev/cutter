import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/clip_drawing.dart';
import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/import_media.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/domain/time_range.dart';

/// How long a new drawing shows, in milliseconds.
const defaultDrawingDurationMs = 3000;

/// Adds a drawing, already rendered to a PNG, as an image clip at its start
/// time: on the first image layer where it fits, or on a new
/// image layer in front of everything.
class AddDrawingClip {
  /// Creates the use case over the given project storage and id source.
  AddDrawingClip(this._projects, this._ids);

  final ProjectRepository _projects;
  final IdGenerator _ids;

  /// Adds [drawing], whose picture is the [width] x [height] PNG at
  /// [sourceUri], to project [projectId].
  Future<EditorResult<Project>> call({
    required String projectId,
    required ClipDrawing drawing,
    required String sourceUri,
    required int width,
    required int height,
    required int startMs,
    int durationMs = defaultDrawingDurationMs,
  }) async {
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    if (drawing.isBlank) return const Err(InvalidDrawing());
    if (startMs < 0) return const Err(NegativeStart());

    final range = TimeRange(startMs, durationMs);
    Layer? target;
    for (final layer in project.layers) {
      if (layer.kind != MediaKind.image) continue;
      if (layer.clips.every((c) => !c.range.overlaps(range))) {
        target = layer;
        break;
      }
    }
    final layer =
        target ?? Layer(id: _ids.next(), name: '', kind: MediaKind.image);
    final clip = Clip(
      id: _ids.next(),
      layerId: layer.id,
      assetId: sourceUri,
      sourceUri: sourceUri,
      kind: MediaKind.image,
      startMs: startMs,
      inPointMs: 0,
      outPointMs: durationMs,
      sourceDurationMs: maxImageDurationMs,
      sourceWidth: width,
      sourceHeight: height,
      drawing: drawing,
    );
    final withClip = layer.withClips([...layer.clips, clip]);
    final updated = target == null
        ? project.withLayers([withClip, ...project.layers])
        : project.replaceLayer(withClip);
    await _projects.save(updated);
    return Ok(updated);
  }
}

/// Gives a drawing clip new strokes and the PNG rendered from them; its
/// place, size, look and length stay.
class SetClipDrawing {
  /// Creates the use case over [_projects].
  SetClipDrawing(this._projects);

  final ProjectRepository _projects;

  /// Replaces the strokes of clip [clipId] with [drawing], now rendered at
  /// [sourceUri] as a [width] x [height] picture.
  Future<EditorResult<Project>> call({
    required String projectId,
    required String clipId,
    required ClipDrawing drawing,
    required String sourceUri,
    required int width,
    required int height,
  }) async {
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    final clip = project.clipById(clipId);
    if (clip == null) return Err(ClipNotFound(clipId));
    if (clip.drawing == null || drawing.isBlank) {
      return const Err(InvalidDrawing());
    }
    final layer = project.layerOfClip(clipId)!;
    final changed = layer.withClips([
      for (final c in layer.clips)
        if (c.id == clipId)
          c.copyWith(
            drawing: drawing,
            sourceUri: sourceUri,
            assetId: sourceUri,
            sourceWidth: width,
            sourceHeight: height,
          )
        else
          c,
    ]);
    final updated = project.replaceLayer(changed);
    await _projects.save(updated);
    return Ok(updated);
  }
}
