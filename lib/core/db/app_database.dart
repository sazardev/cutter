import 'dart:io';

import 'package:cutter/core/db/app_database.steps.dart';
import 'package:cutter/core/db/migrations/from1To2.dart';
import 'package:cutter/core/db/migrations/from2To3.dart';
import 'package:cutter/core/db/migrations/from3To4.dart';
import 'package:cutter/core/db/migrations/from4To5.dart';
import 'package:cutter/core/db/migrations/from5To6.dart';
import 'package:cutter/core/db/migrations/from6To7.dart';
import 'package:cutter/core/db/migrations/from7To8.dart';

import 'package:cutter/core/db/tables/app_settings_table.dart';
import 'package:cutter/features/editor/data/tables/editor_tables.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Milliseconds SQLite waits for a lock before failing a write.
const _busyTimeoutMs = 5000;

/// The name of the database file, without a directory.
const _databaseFileName = 'cutter.sqlite';

/// The local source of truth: editor projects, layers and clips, plus the
/// device-level settings.
@DriftDatabase(
  tables: [
    EditorProjects,
    EditorLayers,
    EditorClips,
    EditorVersions,
    EditorExports,
    EditorMedia,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Creates the database on the given [executor].
  AppDatabase(super.executor);

  /// In-memory database for tests, with the real migrations applied.
  AppDatabase.inMemory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) => migrator.createAll(),
        onUpgrade: stepByStep(
          from1To2: migrateFrom1To2,
          from2To3: migrateFrom2To3,
          from3To4: migrateFrom3To4,
          from4To5: migrateFrom4To5,
          from5To6: migrateFrom5To6,
          from6To7: migrateFrom6To7,
          from7To8: migrateFrom7To8,
        ),
        beforeOpen: (details) async {
          await customStatement('PRAGMA journal_mode=WAL');
          await customStatement('PRAGMA foreign_keys=ON');
          await customStatement('PRAGMA busy_timeout=$_busyTimeoutMs');
        },
      );
}

/// Opens the file-backed database used by the running app.
///
/// The file comes from `DATABASE_PATH` (see `.env.example`). A relative path
/// resolves against the platform's documents directory, the only place a
/// phone lets the app write to; an absolute path is taken as it is, which is
/// what the container deployment of STACK.md needs.
AppDatabase openAppDatabase() {
  return AppDatabase(
    driftDatabase(
      name: 'cutter',
      native: const DriftNativeOptions(databasePath: _databasePath),
    ),
  );
}

/// The path of the database file, with its directory created.
Future<String> _databasePath() async {
  final configured = const String.fromEnvironment('DATABASE_PATH').trim();
  final documents = await getApplicationDocumentsDirectory();

  final file = configured.isEmpty
      ? resolveDatabaseFile(_databaseFileName, documents.path)
      : resolveDatabaseFile(configured, documents.path);
  await file.parent.create(recursive: true);
  return file.path;
}

/// The file of the database, from the configured [path].
///
/// A relative path resolves against [documentsPath], the only place a phone
/// lets the app write to; an absolute path is taken as it is, which is what
/// the container deployment of STACK.md needs.
File resolveDatabaseFile(String path, String documentsPath) {
  final file = File(path);
  if (file.isAbsolute) return file;
  return File(_join(documentsPath, path));
}

/// Joins a directory and a relative path with the separator of the platform.
String _join(String directory, String relative) =>
    '$directory${Platform.pathSeparator}$relative';
