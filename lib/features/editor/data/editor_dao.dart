import 'package:cutter/core/db/app_database.dart';
import 'package:drift/drift.dart';

/// The stored rows of one project: its header, layers and clips.
class ProjectRows {
  /// Bundles the stored header, layers and clips of one project.
  const ProjectRows({
    required this.project,
    required this.layers,
    required this.clips,
  });

  /// The project header row.
  final EditorProject project;

  /// The project's layer rows, ordered by position.
  final List<EditorLayer> layers;

  /// The clip rows of all the project's layers, ordered by sort key.
  final List<EditorClip> clips;
}

/// Typed queries for loading and replacing a whole editor project.
class EditorDao {
  /// Creates the DAO on top of the app database.
  EditorDao(this._db);

  final AppDatabase _db;

  /// Loads a project with layers ordered by position and clips by sort key.
  /// Returns null when the id is unknown.
  Future<ProjectRows?> loadProjectRows(String id) async {
    final project = await (_db.select(_db.editorProjects)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (project == null) {
      return null;
    }

    final layers = await (_db.select(_db.editorLayers)
          ..where((row) => row.projectId.equals(id))
          ..orderBy([(row) => OrderingTerm.asc(row.position)]))
        .get();

    final layerIds = layers.map((layer) => layer.id).toList();
    final clips = await (_db.select(_db.editorClips)
          ..where((row) => row.layerId.isIn(layerIds))
          ..orderBy([(row) => OrderingTerm.asc(row.sortKey)]))
        .get();

    return ProjectRows(project: project, layers: layers, clips: clips);
  }

  /// Replaces the project's layer and clip rows in one transaction, so a
  /// failure leaves the previous rows intact.
  Future<void> replaceProject(ProjectRows rows) {
    return _db.transaction(() async {
      final projectId = rows.project.id;

      await _db.into(_db.editorProjects).insertOnConflictUpdate(rows.project);
      await _deleteLayersAndClips(projectId);

      for (final layer in rows.layers) {
        await _db.into(_db.editorLayers).insert(layer);
      }
      for (final clip in rows.clips) {
        await _db.into(_db.editorClips).insert(clip);
      }
    });
  }

  /// The oldest project id, or null when no project is stored.
  Future<String?> firstProjectId() async {
    final project = await (_db.select(_db.editorProjects)
          ..orderBy([(row) => OrderingTerm.asc(row.createdAtMs)])
          ..limit(1))
        .getSingleOrNull();
    return project?.id;
  }

  Future<void> _deleteLayersAndClips(String projectId) async {
    final oldLayers = await (_db.select(_db.editorLayers)
          ..where((row) => row.projectId.equals(projectId)))
        .get();
    final oldLayerIds = oldLayers.map((layer) => layer.id).toList();

    await (_db.delete(_db.editorClips)
          ..where((row) => row.layerId.isIn(oldLayerIds)))
        .go();
    await (_db.delete(_db.editorLayers)
          ..where((row) => row.projectId.equals(projectId)))
        .go();
  }
}
