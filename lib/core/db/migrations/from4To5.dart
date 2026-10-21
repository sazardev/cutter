// The file name follows the migration steps of the project, not the Dart
// style for file names.
// ignore_for_file: file_names

import 'package:cutter/core/db/app_database.steps.dart';
import 'package:drift/drift.dart';

/// Version 5 adds what the clip editors change and the library of rendered
/// videos.
///
/// - `editor_clips` gains a crop, a speed and sound fades; the defaults keep
///   the whole picture at normal speed without fades, so version 4 clips
///   play exactly as before.
/// - `editor_exports` remembers every rendered video.
Future<void> migrateFrom4To5(Migrator migrator, Schema5 schema) async {
  final clips = schema.editorClips;
  for (final column in [
    clips.cropLeft,
    clips.cropTop,
    clips.cropRight,
    clips.cropBottom,
    clips.speed,
    clips.fadeInMs,
    clips.fadeOutMs,
  ]) {
    await migrator.addColumn(clips, column);
  }
  await migrator.createTable(schema.editorExports);
}
