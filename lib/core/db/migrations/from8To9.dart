// The file name follows the migration steps of the project, not the Dart
// style for file names.
// ignore_for_file: file_names

import 'package:cutter/core/db/app_database.steps.dart';
import 'package:drift/drift.dart';

/// Version 9 adds drawings: `editor_clips` gains `drawing_json`, the strokes
/// of a drawing clip. It is null for every clip written before.
Future<void> migrateFrom8To9(Migrator migrator, Schema9 schema) async {
  await migrator.addColumn(schema.editorClips, schema.editorClips.drawingJson);
}
