// The file name follows the migration steps of the project, not the Dart
// style for file names.
// ignore_for_file: file_names

import 'package:cutter/core/db/app_database.steps.dart';
import 'package:drift/drift.dart';

/// Version 3 adds `app_settings`, a key/value table for device-level
/// settings; the first one remembers that the onboarding was seen.
Future<void> migrateFrom2To3(Migrator migrator, Schema3 schema) async {
  await migrator.createTable(schema.appSettings);
}
