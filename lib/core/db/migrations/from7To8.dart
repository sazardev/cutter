// The file name follows the migration steps of the project, not the Dart
// style for file names.
// ignore_for_file: file_names

import 'package:cutter/core/db/app_database.steps.dart';
import 'package:drift/drift.dart';

/// Version 8 adds clip animations: `editor_clips` gains the id and the
/// length of an entrance and of an exit. The defaults mean no animation, so
/// version 7 clips play exactly as before.
Future<void> migrateFrom7To8(Migrator migrator, Schema8 schema) async {
  final clips = schema.editorClips;
  for (final column in [
    clips.animIn,
    clips.animInMs,
    clips.animOut,
    clips.animOutMs,
  ]) {
    await migrator.addColumn(clips, column);
  }
}
