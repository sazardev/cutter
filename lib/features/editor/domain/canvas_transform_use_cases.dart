import 'package:cutter/features/editor/domain/canvas.dart';
import 'package:cutter/features/editor/domain/clip_transform.dart';
import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';

/// Largest canvas side the engine renders, in pixels (4K).
const maxCanvasSide = 3840;

/// Highest frame rate a canvas may have.
const maxCanvasFps = 120;

/// Changes the frame a project renders to. Clip transforms are stored
/// relative to the canvas, so pictures keep their place.
class SetCanvas {
  /// Creates the use case over [_projects].
  SetCanvas(this._projects);

  final ProjectRepository _projects;

  /// Sets project [projectId] to render to [canvas].
  Future<EditorResult<Project>> call({
    required String projectId,
    required Canvas canvas,
  }) async {
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    final usable = canvas.width >= 16 &&
        canvas.height >= 16 &&
        canvas.width <= maxCanvasSide &&
        canvas.height <= maxCanvasSide &&
        canvas.fps > 0 &&
        canvas.fps <= maxCanvasFps;
    if (!usable) return const Err(InvalidCanvas());

    final updated = project.withCanvas(canvas);
    await _projects.save(updated);
    return Ok(updated);
  }
}

/// Moves, scales, rotates, mirrors or fades the picture of a clip.
class SetClipTransform {
  /// Creates the use case over [_projects].
  SetClipTransform(this._projects);

  final ProjectRepository _projects;

  /// Gives clip [clipId] of project [projectId] the [transform].
  Future<EditorResult<Project>> call({
    required String projectId,
    required String clipId,
    required ClipTransform transform,
  }) async {
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    final clip = project.clipById(clipId);
    final layer = project.layerOfClip(clipId);
    if (clip == null || layer == null) return Err(ClipNotFound(clipId));
    if (clip.kind == MediaKind.audio) return const Err(IncompatibleClip());
    if (!transform.isValid) return const Err(InvalidTransform());

    final updated = project.replaceLayer(
      layer.withClips([
        for (final other in layer.clips)
          if (other.id == clipId)
            other.copyWith(transform: transform)
          else
            other,
      ]),
    );
    await _projects.save(updated);
    return Ok(updated);
  }
}
