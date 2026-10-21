// The file name follows the migration steps of the project, not the Dart
// style for file names.
// ignore_for_file: file_names

import 'package:cutter/core/db/app_database.steps.dart';
import 'package:drift/drift.dart';

/// Version 6 adds the media bank: the files imported into each project,
/// ready to be placed on the timeline again. The files already used by
/// version 5 clips are put into their project's bank, so no project starts
/// with an empty bank.
Future<void> migrateFrom5To6(Migrator migrator, Schema6 schema) async {
  await migrator.createTable(schema.editorMedia);
  await migrator.database.customStatement('''
    INSERT OR IGNORE INTO editor_media
      (id, project_id, path, kind, duration_ms, width, height, has_audio,
       size_bytes, added_at_ms)
    SELECT 'm-' || c.id, l.project_id, c.source_uri, l.kind,
           CASE WHEN l.kind = 'image' THEN 3000
                ELSE COALESCE(c.source_duration_ms, c.out_point_ms) END,
           c.source_width, c.source_height, 0, 0, p.updated_at_ms
    FROM editor_clips c
    JOIN editor_layers l ON l.id = c.layer_id
    JOIN editor_projects p ON p.id = l.project_id
    GROUP BY l.project_id, c.source_uri
  ''');
}
