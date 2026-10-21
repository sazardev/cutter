import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/domain/time_range.dart';

/// The id of the first clip on [layer] that shares time with [range], ignoring
/// the clip [ignoredClipId]; null when the range is free.
String? _firstOverlap(Layer layer, TimeRange range, String ignoredClipId) {
  for (final other in layer.clips) {
    if (other.id != ignoredClipId && other.range.overlaps(range)) {
      return other.id;
    }
  }
  return null;
}

/// [layer] with the clip of the same id as [clip] replaced.
Layer _withReplacedClip(Layer layer, Clip clip) {
  return layer.withClips([
    for (final existing in layer.clips)
      if (existing.id == clip.id) clip else existing,
  ]);
}

/// Shortens or lengthens a clip by moving its in and out points, keeping the
/// timeline position of the frames that remain.
class TrimClip {
  /// Creates the use case over [_projects].
  TrimClip(this._projects);

  final ProjectRepository _projects;

  /// Trims the clip to [inPointMs]..[outPointMs] of its source.
  Future<EditorResult<Project>> call({
    required String projectId,
    required String clipId,
    required int inPointMs,
    required int outPointMs,
  }) async {
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    final clip = project.clipById(clipId);
    final layer = project.layerOfClip(clipId);
    if (clip == null || layer == null) return Err(ClipNotFound(clipId));

    if (outPointMs - inPointMs < minClipDurationMs) {
      return const Err(ZeroDuration());
    }
    if (inPointMs < 0 || outPointMs > clip.sourceDurationMs) {
      return const Err(TrimOutOfSource());
    }

    final newStart = clip.startMs + (inPointMs - clip.inPointMs);
    if (newStart < 0) return const Err(NegativeStart());

    final trimmed = clip.copyWith(
      startMs: newStart,
      inPointMs: inPointMs,
      outPointMs: outPointMs,
    );
    final blocker = _firstOverlap(layer, trimmed.range, clip.id);
    if (blocker != null) return Err(Overlap(blocker));

    final updated = project.replaceLayer(_withReplacedClip(layer, trimmed));
    await _projects.save(updated);
    return Ok(updated);
  }
}

/// Splits a clip in two at a time strictly inside it, with no gap.
class SplitClip {
  /// Creates the use case over [_projects] and [_ids].
  SplitClip(this._projects, this._ids);

  final ProjectRepository _projects;
  final IdGenerator _ids;

  /// Splits the clip at timeline time [atMs].
  Future<EditorResult<Project>> call({
    required String projectId,
    required String clipId,
    required int atMs,
  }) async {
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    final clip = project.clipById(clipId);
    final layer = project.layerOfClip(clipId);
    if (clip == null || layer == null) return Err(ClipNotFound(clipId));
    if (!clip.range.containsStrictly(atMs)) {
      return const Err(PlayheadOutsideClip());
    }

    final firstDurationMs = atMs - clip.startMs;
    // A reversed clip plays its source backwards, so the first timeline half
    // holds the end of the source range.
    final sourceCutMs = clip.reversed
        ? clip.outPointMs - firstDurationMs
        : clip.inPointMs + firstDurationMs;
    final first = clip.reversed
        ? clip.copyWith(inPointMs: sourceCutMs)
        : clip.copyWith(outPointMs: sourceCutMs);
    final second = clip.reversed
        ? clip.copyWith(
            id: _ids.next(),
            startMs: atMs,
            outPointMs: sourceCutMs,
          )
        : clip.copyWith(
            id: _ids.next(),
            startMs: atMs,
            inPointMs: sourceCutMs,
          );

    final updatedLayer = layer.withClips([
      for (final existing in layer.clips)
        if (existing.id == clip.id) ...[first, second] else existing,
    ]);
    final updated = project.replaceLayer(updatedLayer);
    await _projects.save(updated);
    return Ok(updated);
  }
}

/// Moves a clip in time and, optionally, to another layer of the same kind.
/// An overlap is rejected; no clip is ever deleted.
class MoveClip {
  /// Creates the use case over [_projects].
  MoveClip(this._projects);

  final ProjectRepository _projects;

  /// Moves the clip to [startMs] on the layer [targetLayerId].
  Future<EditorResult<Project>> call({
    required String projectId,
    required String clipId,
    required String targetLayerId,
    required int startMs,
  }) async {
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    final clip = project.clipById(clipId);
    final sourceLayer = project.layerOfClip(clipId);
    if (clip == null || sourceLayer == null) return Err(ClipNotFound(clipId));
    final targetLayer = project.layerById(targetLayerId);
    if (targetLayer == null) return Err(LayerNotFound(targetLayerId));
    if (startMs < 0) return const Err(NegativeStart());
    if (targetLayer.kind != clip.kind) return const Err(WrongLayerKind());

    final moved = clip.copyWith(layerId: targetLayer.id, startMs: startMs);
    final blocker = _firstOverlap(targetLayer, moved.range, clip.id);
    if (blocker != null) return Err(Overlap(blocker));

    final updated = _place(project, sourceLayer, targetLayer, moved);
    await _projects.save(updated);
    return Ok(updated);
  }

  Project _place(Project project, Layer source, Layer target, Clip moved) {
    if (source.id == target.id) {
      return project.replaceLayer(_withReplacedClip(source, moved));
    }
    return project.withLayers([
      for (final layer in project.layers)
        if (layer.id == source.id)
          layer.withClips([
            for (final c in layer.clips)
              if (c.id != moved.id) c,
          ])
        else if (layer.id == target.id)
          layer.withClips([...layer.clips, moved])
        else
          layer,
    ]);
  }
}
