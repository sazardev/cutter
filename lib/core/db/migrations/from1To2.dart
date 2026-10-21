// The file name follows the migration steps of the project, not the Dart
// style for file names.
// ignore_for_file: file_names

import 'package:cutter/core/db/app_database.steps.dart';
import 'package:drift/drift.dart';

/// Version 2 stores the duration of the source media of every clip.
///
/// Version 1 rebuilt that duration from the out point, so a clip that had
/// been trimmed forgot how long its source was. The column is nullable
/// because the rows of version 1 do not have it; the repository falls back
/// to the out point for them, which is what version 1 did.
Future<void> migrateFrom1To2(Migrator migrator, Schema2 schema) async {
  await migrator.addColumn(
    schema.editorClips,
    schema.editorClips.sourceDurationMs,
  );
}
