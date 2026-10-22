// The file name follows the migration steps of the project, not the Dart
// style for file names.
// `TableMigration` is the documented way to rebuild a table in drift.
// ignore_for_file: file_names, experimental_member_use

import 'package:cutter/core/db/app_database.steps.dart';
import 'package:drift/drift.dart';

/// Version 7 adds text clips.
///
/// - `editor_clips` gains `text_json`, the words and look of a text clip;
///   it is null for every clip written before.
/// - `editor_layers.kind` now accepts `text`. Its CHECK constraint cannot be
///   altered in place, so the table is rebuilt with the new one and its rows
///   are copied as they are.
Future<void> migrateFrom6To7(Migrator migrator, Schema7 schema) async {
  await migrator.addColumn(schema.editorClips, schema.editorClips.textJson);
  await migrator.alterTable(TableMigration(schema.editorLayers));
}
