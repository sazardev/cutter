import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/features/editor/data/engine_timeline.dart';
import 'package:cutter/features/storage/data/storage_scanner.dart';

/// Which files each project's clips use, read straight from the database
/// (three queries, whatever the number of projects).
Future<List<ProjectMedia>> readProjectMedia(
  AppDatabase db, {
  Set<String> trashedIds = const {},
}) async {
  final projects = await db.select(db.editorProjects).get();
  final layers = await db.select(db.editorLayers).get();
  final clips = await db.select(db.editorClips).get();

  final projectOfLayer = {for (final l in layers) l.id: l.projectId};
  final paths = <String, Set<String>>{};
  for (final clip in clips) {
    final projectId = projectOfLayer[clip.layerId];
    if (projectId == null) continue;
    (paths[projectId] ??= {}).add(filePathOf(clip.sourceUri));
  }
  return [
    for (final project in projects)
      ProjectMedia(
        id: project.id,
        name: project.name,
        paths: paths[project.id] ?? const {},
        trashed: trashedIds.contains(project.id),
      ),
  ];
}
