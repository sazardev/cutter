import 'package:cutter/features/editor/data/tables/editor_tables.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// Milliseconds SQLite waits for a lock before failing a write.
const _busyTimeoutMs = 5000;

/// The local source of truth: editor projects, layers and clips.
@DriftDatabase(tables: [EditorProjects, EditorLayers, EditorClips])
class AppDatabase extends _$AppDatabase {
  /// Creates the database on the given [executor].
  AppDatabase(super.executor);

  /// In-memory database for tests, with the real migrations applied.
  AppDatabase.inMemory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) => migrator.createAll(),
        beforeOpen: (details) async {
          await customStatement('PRAGMA journal_mode=WAL');
          await customStatement('PRAGMA foreign_keys=ON');
          await customStatement('PRAGMA busy_timeout=$_busyTimeoutMs');
        },
      );
}

/// Opens the file-backed database used by the running app.
AppDatabase openAppDatabase() {
  return AppDatabase(driftDatabase(name: 'cutter'));
}
