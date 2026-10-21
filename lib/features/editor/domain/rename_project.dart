import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/project.dart';

/// The longest name a project can have.
const int maxProjectNameLength = 80;

/// Gives a project another name, stored at once like any other edit.
class RenameProject {
  /// Creates the use case over [_projects].
  RenameProject(this._projects);

  final ProjectRepository _projects;

  /// Names project [projectId] [name]; blank names are rejected and long
  /// ones are cut to [maxProjectNameLength].
  Future<EditorResult<Project>> call({
    required String projectId,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const Err(EmptyName());
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    final fitted = trimmed.length > maxProjectNameLength
        ? trimmed.substring(0, maxProjectNameLength).trimRight()
        : trimmed;
    final updated = project.withName(fitted);
    await _projects.save(updated);
    return Ok(updated);
  }
}
