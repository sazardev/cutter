import 'package:cutter/features/editor/domain/canvas.dart';
import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/project.dart';

/// Creates and saves a new project, empty or laid out like a template.
///
/// A project from a template starts with the template's layers and no clips:
/// the media slots are filled later, once the user can import media. Nothing
/// is saved when the name is blank or the template is unknown.
class CreateProject {
  /// Creates the use case over its ports.
  CreateProject(this._projects, this._templates, this._ids);

  final ProjectRepository _projects;
  final TemplateCatalog _templates;
  final IdGenerator _ids;

  /// Creates a project named [name]; [templateId] gives it the layers of that
  /// template and [canvas] sets its frame (the default portrait one when
  /// null).
  Future<EditorResult<Project>> call({
    required String name,
    String? templateId,
    Canvas? canvas,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const Err(EmptyName());

    final layers = <Layer>[];
    if (templateId != null) {
      final template = await _templates.find(templateId);
      if (template == null) return Err(TemplateNotFound(templateId));
      for (final layer in template.layers) {
        layers.add(Layer(id: _ids.next(), name: layer.name, kind: layer.kind));
      }
    }

    final project = Project(
      id: _ids.next(),
      name: trimmed,
      layers: layers,
      templateId: templateId,
      canvas: canvas ?? defaultCanvas,
    );
    await _projects.save(project);
    return Ok(project);
  }
}
