import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/preset.dart';
import 'package:cutter/features/editor/domain/project.dart';

/// Saves the filter, adjustments and volume of a clip as a named preset.
class SavePreset {
  /// Creates the use case over its ports.
  SavePreset(this._projects, this._presets, this._ids);

  final ProjectRepository _projects;
  final PresetRepository _presets;
  final IdGenerator _ids;

  /// Saves the settings of clip [clipId] as a preset called [name].
  Future<EditorResult<Preset>> call({
    required String projectId,
    required String clipId,
    required String name,
  }) async {
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    final clip = project.clipById(clipId);
    if (clip == null) return Err(ClipNotFound(clipId));
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return const Err(EmptyName());

    final preset = Preset(
      id: _ids.next(),
      name: trimmedName,
      filterId: clip.filterId,
      adjustments: Map<String, double>.of(clip.adjustments),
      volume: clip.volume,
    );
    await _presets.save(preset);
    return Ok(preset);
  }
}

/// Applies every captured setting of a preset to a clip.
class ApplyPreset {
  /// Creates the use case over its ports.
  ApplyPreset(this._projects, this._presets);

  final ProjectRepository _projects;
  final PresetRepository _presets;

  /// Applies preset [presetId] to clip [clipId] and saves the project.
  Future<EditorResult<Project>> call({
    required String projectId,
    required String clipId,
    required String presetId,
  }) async {
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    final clip = project.clipById(clipId);
    final layer = project.layerOfClip(clipId);
    if (clip == null || layer == null) return Err(ClipNotFound(clipId));
    final preset = await _presets.find(presetId);
    if (preset == null) return Err(PresetNotFound(presetId));
    if (preset.filterId != null && clip.kind == MediaKind.audio) {
      return const Err(IncompatibleClip());
    }

    final updated = clip.copyWith(
      volume: preset.volume,
      adjustments: Map<String, double>.of(preset.adjustments),
      filterId: preset.filterId,
      clearFilter: preset.filterId == null,
    );
    final changedLayer = layer.withClips([
      for (final existing in layer.clips)
        if (existing.id == clipId) updated else existing,
    ]);
    final changed = project.replaceLayer(changedLayer);
    await _projects.save(changed);
    return Ok(changed);
  }
}
