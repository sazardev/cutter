import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/features/editor/domain/project_summary.dart';
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

  /// One summary per stored project, the most recently saved first.
  ///
  /// Reads the three tables once each, so the cost does not grow with the
  /// number of projects.
  Future<List<ProjectSummary>> summaries() async {
    final projects = await (_db.select(_db.editorProjects)
          ..orderBy([(row) => OrderingTerm.desc(row.updatedAtMs)]))
        .get();
    final layers = await _db.select(_db.editorLayers).get();
    final clips = await _db.select(_db.editorClips).get();

    final projectOfLayer = {
      for (final layer in layers) layer.id: layer.projectId,
    };
    final layerCount = <String, int>{};
    for (final layer in layers) {
      layerCount[layer.projectId] = (layerCount[layer.projectId] ?? 0) + 1;
    }
    final layerById = {for (final layer in layers) layer.id: layer};
    final clipCount = <String, int>{};
    final durationMs = <String, int>{};
    // The first picture or video clip of each project is its cover: the
    // earliest on the timeline, then the lowest layer.
    final cover = <String, EditorClip>{};
    for (final clip in clips) {
      final projectId = projectOfLayer[clip.layerId];
      if (projectId == null) continue;
      final layer = layerById[clip.layerId]!;
      if (layer.kind != 'audio') {
        final best = cover[projectId];
        final bestLayer = best == null ? null : layerById[best.layerId]!;
        if (best == null ||
            clip.startMs < best.startMs ||
            (clip.startMs == best.startMs &&
                layer.position < bestLayer!.position)) {
          cover[projectId] = clip;
        }
      }
      clipCount[projectId] = (clipCount[projectId] ?? 0) + 1;
      final end = clip.startMs + clip.durationMs;
      if (end > (durationMs[projectId] ?? 0)) durationMs[projectId] = end;
    }

    return [
      for (final project in projects)
        ProjectSummary(
          id: project.id,
          name: project.name,
          layerCount: layerCount[project.id] ?? 0,
          clipCount: clipCount[project.id] ?? 0,
          durationMs: durationMs[project.id] ?? 0,
          updatedAtMs: project.updatedAtMs,
          savedAtMs: project.savedAtMs,
          coverUri: cover[project.id]?.sourceUri,
          coverMs: cover[project.id]?.inPointMs ?? 0,
        ),
    ];
  }

  /// Deletes the project with its layers, clips and saved versions, and
  /// unlinks its exports and media-bank rows, in one transaction. Done by
  /// hand so it does not depend on the foreign keys being enforced.
  Future<void> deleteProject(String id) {
    return _db.transaction(() async {
      await _deleteLayersAndClips(id);
      await (_db.delete(_db.editorVersions)
            ..where((row) => row.projectId.equals(id)))
          .go();
      await (_db.update(_db.editorExports)
            ..where((row) => row.projectId.equals(id)))
          .write(const EditorExportsCompanion(projectId: Value(null)));
      await (_db.update(_db.editorMedia)
            ..where((row) => row.projectId.equals(id)))
          .write(const EditorMediaCompanion(projectId: Value(null)));
      await (_db.delete(_db.editorProjects)..where((row) => row.id.equals(id)))
          .go();
    });
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
