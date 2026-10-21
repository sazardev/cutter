import 'dart:io';

import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/features/editor/domain/export_record.dart';
import 'package:drift/drift.dart';

/// Drift-backed [ExportLibrary]. Files deleted outside the app are noticed
/// when the library is listed and their rows removed.
class DriftExportLibrary implements ExportLibrary {
  /// Creates the library on [_db]; [exists] checks a file, replaceable in
  /// tests.
  DriftExportLibrary(this._db, {bool Function(String path)? exists})
      : _exists = exists ?? ((path) => File(path).existsSync());

  final AppDatabase _db;
  final bool Function(String path) _exists;

  @override
  Future<void> add(ExportRecord record) async {
    await _db.into(_db.editorExports).insertOnConflictUpdate(
          EditorExport(
            id: record.id,
            projectId: record.projectId,
            projectName: record.projectName,
            path: record.path,
            width: record.width,
            height: record.height,
            fps: record.fps,
            durationMs: record.durationMs,
            sizeBytes: record.sizeBytes,
            createdAtMs: record.createdAtMs,
            preset: record.preset,
            inGallery: record.inGallery,
          ),
        );
  }

  @override
  Future<List<ExportRecord>> all() async {
    final rows = await (_db.select(_db.editorExports)
          ..orderBy([(row) => OrderingTerm.desc(row.createdAtMs)]))
        .get();
    final gone = [
      for (final row in rows)
        if (!_exists(row.path)) row.id,
    ];
    if (gone.isNotEmpty) {
      await (_db.delete(_db.editorExports)..where((r) => r.id.isIn(gone))).go();
    }
    return [
      for (final row in rows)
        if (!gone.contains(row.id))
          ExportRecord(
            id: row.id,
            path: row.path,
            projectId: row.projectId,
            projectName: row.projectName,
            width: row.width,
            height: row.height,
            fps: row.fps,
            durationMs: row.durationMs,
            sizeBytes: row.sizeBytes,
            createdAtMs: row.createdAtMs,
            preset: row.preset,
            inGallery: row.inGallery,
          ),
    ];
  }

  @override
  Future<void> remove(String id) async {
    final row = await (_db.select(_db.editorExports)
          ..where((r) => r.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return;
    final file = File(row.path);
    if (file.existsSync()) await file.delete();
    await (_db.delete(_db.editorExports)..where((r) => r.id.equals(id))).go();
  }
}
