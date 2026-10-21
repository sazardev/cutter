// The file name follows the migration steps of the project, not the Dart
// style for file names.
// ignore_for_file: file_names

import 'package:cutter/core/db/app_database.steps.dart';
import 'package:drift/drift.dart';

/// Version 4 lets pictures be placed on the canvas and adds saved versions.
///
/// - `editor_clips` gains the transform of a clip (position, scale,
///   rotation, opacity, mirror, fit) and the display size of its source.
///   Every column has a default that means "fitted and centred", so the
///   rows of version 3 look exactly as before.
/// - `editor_projects` gains `saved_at_ms`, null until a version is saved:
///   every existing project starts as a draft.
/// - `editor_versions` keeps the named versions with a JSON snapshot.
Future<void> migrateFrom3To4(Migrator migrator, Schema4 schema) async {
  final clips = schema.editorClips;
  for (final column in [
    clips.posX,
    clips.posY,
    clips.scale,
    clips.rotation,
    clips.opacity,
    clips.flipX,
    clips.fit,
    clips.sourceWidth,
    clips.sourceHeight,
  ]) {
    await migrator.addColumn(clips, column);
  }
  await migrator.addColumn(
    schema.editorProjects,
    schema.editorProjects.savedAtMs,
  );
  await migrator.createTable(schema.editorVersions);
}
