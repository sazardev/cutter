import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/project.dart';

/// Removes a clip. With ripple, the later clips of its layer move back to
/// close the gap, as on a main track.
class DeleteClip {
  /// Creates the use case over [_projects].
  DeleteClip(this._projects);

  final ProjectRepository _projects;

  /// Deletes clip [clipId] of project [projectId].
  Future<EditorResult<Project>> call({
    required String projectId,
    required String clipId,
    bool ripple = false,
  }) async {
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    final clip = project.clipById(clipId);
    final layer = project.layerOfClip(clipId);
    if (clip == null || layer == null) return Err(ClipNotFound(clipId));

    final updated = project.replaceLayer(
      layer.withClips([
        for (final other in layer.clips)
          if (other.id == clipId)
            ...[]
          else if (ripple && other.startMs >= clip.range.endMs)
            other.copyWith(startMs: other.startMs - clip.durationMs)
          else
            other,
      ]),
    );
    await _projects.save(updated);
    return Ok(updated);
  }
}

/// Copies a clip right after itself on the same layer; the later clips of
/// the layer move on to make room.
class DuplicateClip {
  /// Creates the use case over the given project storage and id source.
  DuplicateClip(this._projects, this._ids);

  final ProjectRepository _projects;
  final IdGenerator _ids;

  /// Duplicates clip [clipId] of project [projectId].
  Future<EditorResult<Project>> call({
    required String projectId,
    required String clipId,
  }) async {
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    final clip = project.clipById(clipId);
    final layer = project.layerOfClip(clipId);
    if (clip == null || layer == null) return Err(ClipNotFound(clipId));

    final end = clip.range.endMs;
    final copy = clip.copyWith(id: _ids.next(), startMs: end);
    final updated = project.replaceLayer(
      layer.withClips([
        for (final other in layer.clips)
          if (other.id != clip.id && other.startMs >= end)
            other.copyWith(startMs: other.startMs + clip.durationMs)
          else
            other,
        copy,
      ]),
    );
    await _projects.save(updated);
    return Ok(updated);
  }
}

/// Silences or restores a whole layer.
class SetLayerMuted {
  /// Creates the use case over [_projects].
  SetLayerMuted(this._projects);

  final ProjectRepository _projects;

  /// Sets layer [layerId] of project [projectId] to [muted].
  Future<EditorResult<Project>> call({
    required String projectId,
    required String layerId,
    required bool muted,
  }) async {
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    final layer = project.layerById(layerId);
    if (layer == null) return Err(LayerNotFound(layerId));

    final updated = project.replaceLayer(layer.copyWith(muted: muted));
    await _projects.save(updated);
    return Ok(updated);
  }
}

/// Removes a layer together with its clips.
class DeleteLayer {
  /// Creates the use case over [_projects].
  DeleteLayer(this._projects);

  final ProjectRepository _projects;

  /// Deletes layer [layerId] of project [projectId].
  Future<EditorResult<Project>> call({
    required String projectId,
    required String layerId,
  }) async {
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    if (project.layerById(layerId) == null) return Err(LayerNotFound(layerId));

    final updated = project.withLayers([
      for (final layer in project.layers)
        if (layer.id != layerId) layer,
    ]);
    await _projects.save(updated);
    return Ok(updated);
  }
}

/// Stores an earlier version of a project as the current one: the step
/// behind undo and redo.
class RestoreProject {
  /// Creates the use case over [_projects].
  RestoreProject(this._projects);

  final ProjectRepository _projects;

  /// Saves [snapshot] in place of the stored project with the same id.
  Future<EditorResult<Project>> call(Project snapshot) async {
    await _projects.save(snapshot);
    return Ok(snapshot);
  }
}
