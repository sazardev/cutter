import 'dart:io';

import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/media_bank.dart';
import 'package:drift/drift.dart';

/// Drift-backed [MediaBank]. Files deleted from the device are noticed when
/// a bank is listed and their rows dropped.
class DriftMediaBank implements MediaBank {
  /// Creates the bank on [_db]; [exists] checks a file, replaceable in
  /// tests.
  DriftMediaBank(this._db, {bool Function(String path)? exists})
      : _exists = exists ?? ((path) => File(path).existsSync());

  final AppDatabase _db;
  final bool Function(String path) _exists;

  MediaItem _item(EditorMediaItem row) => MediaItem(
        id: row.id,
        projectId: row.projectId,
        path: row.path,
        kind: MediaKind.values.byName(row.kind),
        durationMs: row.durationMs,
        width: row.width,
        height: row.height,
        hasAudio: row.hasAudio,
        sizeBytes: row.sizeBytes,
        addedAtMs: row.addedAtMs,
      );

  Future<List<EditorMediaItem>> _alive(List<EditorMediaItem> rows) async {
    final gone = [
      for (final r in rows)
        if (!_exists(r.path)) r.id,
    ];
    if (gone.isNotEmpty) {
      await (_db.delete(_db.editorMedia)..where((r) => r.id.isIn(gone))).go();
    }
    return [
      for (final r in rows)
        if (!gone.contains(r.id)) r,
    ];
  }

  @override
  Future<List<MediaItem>> itemsOf(String projectId) async {
    final rows = await (_db.select(_db.editorMedia)
          ..where((r) => r.projectId.equals(projectId))
          ..orderBy([(r) => OrderingTerm.desc(r.addedAtMs)]))
        .get();
    return [for (final r in await _alive(rows)) _item(r)];
  }

  @override
  Future<List<MediaItem>> recent({
    required String exceptProjectId,
    int limit = 60,
  }) async {
    final rows = await (_db.select(_db.editorMedia)
          ..where(
            (r) =>
                r.projectId.isNull() |
                r.projectId.equals(exceptProjectId).not(),
          )
          ..orderBy([(r) => OrderingTerm.desc(r.addedAtMs)]))
        .get();
    final seen = <String>{};
    final out = <MediaItem>[];
    for (final r in await _alive(rows)) {
      if (seen.add(r.path)) out.add(_item(r));
      if (out.length >= limit) break;
    }
    return out;
  }

  @override
  Future<void> add(List<MediaItem> items) {
    return _db.batch((batch) {
      for (final item in items) {
        batch.insert(
          _db.editorMedia,
          EditorMediaCompanion.insert(
            id: item.id,
            projectId: Value(item.projectId),
            path: item.path,
            kind: item.kind.name,
            durationMs: item.durationMs,
            width: Value(item.width),
            height: Value(item.height),
            hasAudio: Value(item.hasAudio),
            sizeBytes:
                Value(item.sizeBytes > 0 ? item.sizeBytes : _sizeOf(item.path)),
            addedAtMs: item.addedAtMs,
          ),
          // The same file twice in one bank stays once.
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  static int _sizeOf(String path) {
    final file = File(path);
    return file.existsSync() ? file.lengthSync() : 0;
  }

  @override
  Future<void> remove(String id) =>
      (_db.delete(_db.editorMedia)..where((r) => r.id.equals(id))).go();
}
