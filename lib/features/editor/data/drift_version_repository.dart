import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/features/editor/data/project_snapshot_codec.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/domain/project_version.dart';
import 'package:drift/drift.dart';

/// Drift-backed [VersionRepository]: one row per version with the project as
/// JSON.
class DriftVersionRepository implements VersionRepository {
  /// Creates the repository on [_db].
  DriftVersionRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<ProjectVersion>> versionsOf(String projectId) async {
    final rows = await (_db.select(_db.editorVersions)
          ..where((row) => row.projectId.equals(projectId))
          ..orderBy([(row) => OrderingTerm.desc(row.createdAtMs)]))
        .get();
    return [
      for (final row in rows)
        ProjectVersion(
          id: row.id,
          projectId: row.projectId,
          name: row.name,
          createdAtMs: row.createdAtMs,
          durationMs: row.durationMs,
        ),
    ];
  }

  @override
  Future<void> save(ProjectVersion version, Project snapshot) {
    // The version and the project's saved time change together or not at
    // all.
    return _db.transaction(() async {
      await _db.into(_db.editorVersions).insert(
            EditorVersionsCompanion.insert(
              id: version.id,
              projectId: version.projectId,
              name: version.name,
              createdAtMs: version.createdAtMs,
              durationMs: Value(version.durationMs),
              snapshotJson: encodeProjectSnapshot(snapshot),
            ),
          );
      await (_db.update(_db.editorProjects)
            ..where((row) => row.id.equals(version.projectId)))
          .write(
        EditorProjectsCompanion(savedAtMs: Value(version.createdAtMs)),
      );
    });
  }

  @override
  Future<Project?> snapshotOf(String versionId) async {
    final row = await (_db.select(_db.editorVersions)
          ..where((r) => r.id.equals(versionId)))
        .getSingleOrNull();
    return row == null ? null : decodeProjectSnapshot(row.snapshotJson);
  }
}
