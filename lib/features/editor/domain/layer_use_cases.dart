import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/domain/time_range.dart';

const double _minVolume = 0;
const double _maxVolume = 1;

bool _isValidVolume(double volume) =>
    volume >= _minVolume && volume <= _maxVolume;

/// Adds an imported media file to a layer as a new clip that plays the whole
/// asset from `startMs`. Nothing is saved when the media is rejected.
class AddClipToLayer {
  /// Creates the use case over the given project storage and id source.
  AddClipToLayer(this._projects, this._ids);

  final ProjectRepository _projects;
  final IdGenerator _ids;

  /// Adds [asset] to layer [layerId] of project [projectId] at [startMs].
  Future<EditorResult<Project>> call({
    required String projectId,
    required String layerId,
    required MediaAsset asset,
    required int startMs,
  }) async {
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    final layer = project.layerById(layerId);
    if (layer == null) return Err(LayerNotFound(layerId));
    if (!asset.supported) return const Err(UnsupportedMedia());
    if (asset.kind != layer.kind) return const Err(WrongLayerKind());
    if (startMs < 0) return const Err(NegativeStart());
    if (asset.durationMs < minClipDurationMs) return const Err(ZeroDuration());

    final range = TimeRange(startMs, asset.durationMs);
    for (final existing in layer.clips) {
      if (existing.range.overlaps(range)) return Err(Overlap(existing.id));
    }

    final clip = Clip(
      id: _ids.next(),
      layerId: layer.id,
      assetId: asset.id,
      sourceUri: asset.uri,
      kind: asset.kind,
      startMs: startMs,
      inPointMs: 0,
      outPointMs: asset.durationMs,
      sourceDurationMs: asset.durationMs,
    );
    final updated =
        project.replaceLayer(layer.withClips([...layer.clips, clip]));
    await _projects.save(updated);
    return Ok(updated);
  }
}

/// Reorders the layers of a project; index 0 becomes the front-most layer.
class ReorderLayers {
  /// Creates the use case over the given project storage.
  ReorderLayers(this._projects);

  final ProjectRepository _projects;

  /// Reorders project [projectId] to follow [layerIds].
  Future<EditorResult<Project>> call({
    required String projectId,
    required List<String> layerIds,
  }) async {
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    if (!_isPermutation(project, layerIds)) {
      return const Err(InvalidLayerOrder());
    }

    final updated = project.withLayers([
      for (final id in layerIds) project.layerById(id)!,
    ]);
    await _projects.save(updated);
    return Ok(updated);
  }

  bool _isPermutation(Project project, List<String> layerIds) {
    if (layerIds.length != project.layers.length) return false;
    final unique = layerIds.toSet();
    if (unique.length != layerIds.length) return false;
    return unique.every((id) => project.layerById(id) != null);
  }
}

/// Sets the volume and mute state of one layer.
class SetLayerVolume {
  /// Creates the use case over the given project storage.
  SetLayerVolume(this._projects);

  final ProjectRepository _projects;

  /// Sets [volume] and [muted] on layer [layerId] of project [projectId].
  Future<EditorResult<Project>> call({
    required String projectId,
    required String layerId,
    required double volume,
    required bool muted,
  }) async {
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    final layer = project.layerById(layerId);
    if (layer == null) return Err(LayerNotFound(layerId));
    if (!_isValidVolume(volume)) return const Err(InvalidVolume());

    final updated =
        project.replaceLayer(layer.copyWith(volume: volume, muted: muted));
    await _projects.save(updated);
    return Ok(updated);
  }
}
