// All fields are final, so the class is immutable; the `meta` package that
// provides `@immutable` is not a declared dependency of the domain.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/project.dart';

/// How much editing passes between two automatic restore points.
const Duration autoCheckpointInterval = Duration(minutes: 10);

/// A restore point: a copy of a project under a name. The project itself is
/// stored on every edit, so nothing is lost by closing the app; a version is
/// a point to go back to. The user saves them by hand, and the editor also
/// saves one when a project opens for the first time, every
/// [autoCheckpointInterval] of editing, and before a restore.
class ProjectVersion {
  /// Creates the description of a saved version.
  const ProjectVersion({
    required this.id,
    required this.projectId,
    required this.name,
    required this.createdAtMs,
    required this.durationMs,
  });

  /// Unique id of the version.
  final String id;

  /// The project it is a version of.
  final String projectId;

  /// The name the user gave it.
  final String name;

  /// When it was saved, in milliseconds since the epoch.
  final int createdAtMs;

  /// The length of the project at that point.
  final int durationMs;

  @override
  bool operator ==(Object other) =>
      other is ProjectVersion &&
      other.id == id &&
      other.projectId == projectId &&
      other.name == name &&
      other.createdAtMs == createdAtMs &&
      other.durationMs == durationMs;

  @override
  int get hashCode => Object.hash(id, projectId, name, createdAtMs, durationMs);
}

/// Storage of saved versions, owned by the domain and implemented at the
/// edge.
abstract interface class VersionRepository {
  /// The versions of project [projectId], the newest first.
  Future<List<ProjectVersion>> versionsOf(String projectId);

  /// Stores [version] with the full [snapshot] of the project, and marks the
  /// project as saved at the version's time.
  Future<void> save(ProjectVersion version, Project snapshot);

  /// The project as it was saved in version [versionId], or null.
  Future<Project?> snapshotOf(String versionId);
}

/// Saves the current state of a project as a named version.
class SaveVersion {
  /// Creates the use case; [now] gives the current time in milliseconds.
  SaveVersion(this._projects, this._versions, this._ids, {int Function()? now})
      : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final ProjectRepository _projects;
  final VersionRepository _versions;
  final IdGenerator _ids;
  final int Function() _now;

  /// Saves project [projectId] as version [name].
  Future<EditorResult<ProjectVersion>> call({
    required String projectId,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const Err(EmptyName());
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));

    final version = ProjectVersion(
      id: _ids.next(),
      projectId: projectId,
      name: trimmed,
      createdAtMs: _now(),
      durationMs: project.durationMs,
    );
    await _versions.save(version, project);
    return Ok(version);
  }
}

/// Puts a project back to how it was in a saved version. The current state
/// is not lost: the editor records it for undo.
class RestoreVersion {
  /// Creates the use case.
  RestoreVersion(this._projects, this._versions);

  final ProjectRepository _projects;
  final VersionRepository _versions;

  /// Restores version [versionId] into project [projectId].
  Future<EditorResult<Project>> call({
    required String projectId,
    required String versionId,
  }) async {
    final snapshot = await _versions.snapshotOf(versionId);
    if (snapshot == null || snapshot.id != projectId) {
      return Err(VersionNotFound(versionId));
    }
    await _projects.save(snapshot);
    return Ok(snapshot);
  }
}
