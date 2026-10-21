import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/domain/template.dart';

/// Creates and saves a new project from a template and the media the user
/// chose for each slot.
///
/// Nothing is created when any slot lacks usable media, so a broken project
/// never exists. The clip of a slot plays the start of its asset, trimmed to
/// the slot duration.
class InstantiateTemplate {
  /// Creates the use case over its ports.
  InstantiateTemplate(this._projects, this._templates, this._ids);

  final ProjectRepository _projects;
  final TemplateCatalog _templates;
  final IdGenerator _ids;

  /// Creates the project from template [templateId] named [name], using
  /// [media] keyed by slot id; returns the failure when any slot is unusable.
  Future<EditorResult<Project>> call({
    required String templateId,
    required String name,
    required Map<String, MediaAsset> media,
  }) async {
    final template = await _templates.find(templateId);
    if (template == null) return Err(TemplateNotFound(templateId));

    final missing = [
      for (final slot in template.slots)
        if (!_isUsable(template, slot, media[slot.id])) slot.id,
    ];
    if (missing.isNotEmpty) return Err(MissingTemplateMedia(missing));

    final project = _buildProject(template, name, media);
    await _projects.save(project);
    return Ok(project);
  }

  bool _isUsable(Template template, MediaSlot slot, MediaAsset? asset) {
    if (asset == null || !asset.supported) return false;
    if (asset.kind != slot.kind) return false;
    if (slot.layerIndex < 0 || slot.layerIndex >= template.layers.length) {
      return false;
    }
    if (template.layers[slot.layerIndex].kind != slot.kind) return false;
    if (slot.startMs < 0) return false;
    return _clipDuration(slot, asset) >= minClipDurationMs;
  }

  int _clipDuration(MediaSlot slot, MediaAsset asset) {
    return slot.durationMs < asset.durationMs
        ? slot.durationMs
        : asset.durationMs;
  }

  Project _buildProject(
    Template template,
    String name,
    Map<String, MediaAsset> media,
  ) {
    final projectId = _ids.next();
    final layerIds = [for (final _ in template.layers) _ids.next()];
    final clipsByLayer = List.generate(template.layers.length, (_) => <Clip>[]);

    for (final slot in template.slots) {
      final asset = media[slot.id]!;
      clipsByLayer[slot.layerIndex].add(
        Clip(
          id: _ids.next(),
          layerId: layerIds[slot.layerIndex],
          assetId: asset.id,
          sourceUri: asset.uri,
          kind: asset.kind,
          startMs: slot.startMs,
          inPointMs: 0,
          outPointMs: _clipDuration(slot, asset),
          sourceDurationMs: asset.durationMs,
        ),
      );
    }

    final layers = [
      for (var index = 0; index < template.layers.length; index++)
        Layer(
          id: layerIds[index],
          name: template.layers[index].name,
          kind: template.layers[index].kind,
          clips: clipsByLayer[index],
        ),
    ];
    return Project(
      id: projectId,
      name: name,
      layers: layers,
      templateId: template.id,
    );
  }
}
