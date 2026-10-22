import 'dart:io';

import 'package:cutter/core/engine/media_engine.dart';
import 'package:cutter/features/editor/data/media_library.dart';
import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/import_limits.dart';
import 'package:cutter/features/editor/domain/import_media.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';

/// Describes picked files with the engine and keeps them where they last.
class EngineMediaInspector implements MediaInspector {
  /// Creates the inspector; [keep] returns the lasting path of a picked
  /// file.
  EngineMediaInspector(this._engine, this._ids, {required this.keep});

  final MediaEngine _engine;
  final IdGenerator _ids;

  /// Moves a picked file to where it will last and returns that path.
  final Future<String> Function(String path) keep;

  @override
  Future<(int, int)?> measure(String path) async {
    try {
      final info = await _engine.probe(path);
      if (info.width <= 0 || info.height <= 0) return null;
      return (info.width, info.height);
    } on Object {
      return null;
    }
  }

  @override
  Future<MediaAsset> inspect(String path) async {
    final MediaInfo info;
    try {
      info = await _engine.probe(path);
    } on Object {
      return MediaAsset(
        id: _ids.next(),
        uri: path,
        kind: MediaKind.video,
        durationMs: 0,
        supported: false,
        issue: ImportIssueKind.unreadable,
      );
    }
    final kind = switch (info.kind) {
      EngineMediaKind.video => MediaKind.video,
      EngineMediaKind.image => MediaKind.image,
      EngineMediaKind.audio => MediaKind.audio,
      EngineMediaKind.text => MediaKind.text,
    };
    final String kept;
    try {
      kept = await keep(path);
    } on MediaStorageFull {
      return _failed(path, kind, ImportIssueKind.storageFull);
    } on Object {
      return _failed(path, kind, ImportIssueKind.copyFailed);
    }
    return MediaAsset(
      id: _ids.next(),
      uri: kept,
      kind: kind,
      sizeBytes: _sizeOf(kept),
      durationMs:
          kind == MediaKind.image ? defaultImageDurationMs : info.durationMs,
      width: info.width,
      height: info.height,
      audioPresent: info.hasAudio,
    );
  }

  MediaAsset _failed(String path, MediaKind kind, ImportIssueKind issue) {
    return MediaAsset(
      id: _ids.next(),
      uri: path,
      kind: kind,
      durationMs: 0,
      supported: false,
      issue: issue,
    );
  }

  int _sizeOf(String path) {
    try {
      return File(path).lengthSync();
    } on FileSystemException {
      return 0;
    }
  }
}
