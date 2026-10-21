import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cutter/features/backup/domain/backup_format.dart';
import 'package:cutter/features/editor/data/engine_timeline.dart';
import 'package:cutter/features/editor/data/project_snapshot_codec.dart';
import 'package:cutter/features/editor/domain/project.dart';

// errno of "no space left on device" on Linux and Android.
const int _noSpaceErrno = 28;

/// What a finished backup holds.
class BackupResult {
  /// Creates the result.
  const BackupResult({
    required this.path,
    required this.mediaCount,
    required this.missingCount,
  });

  /// The backup file.
  final String path;

  /// How many media files went in.
  final int mediaCount;

  /// How many files the project uses that were not there to back up.
  final int missingCount;
}

/// Writes [project] and every media file its clips use into one file at
/// [outPath]: the magic, the format, the manifest, then the media bytes in
/// manifest order. It is written aside and renamed when complete, so a full
/// disk or a crash never leaves a broken backup in place.
///
/// Files the project uses that no longer exist are left out and counted;
/// the restored project shows those clips as missing and lets the user find
/// them again.
Future<BackupResult> writeBackup(
  Project project,
  String outPath, {
  DateTime? now,
}) async {
  final uris = <String>{
    for (final layer in project.layers)
      for (final clip in layer.clips) clip.sourceUri,
  };
  final entries = <BackupEntry>[];
  var missing = 0;
  for (final uri in uris) {
    final file = File(filePathOf(uri));
    if (!file.existsSync()) {
      missing++;
      continue;
    }
    entries.add(
      BackupEntry(
        uri: uri,
        name: file.uri.pathSegments.last,
        size: file.lengthSync(),
      ),
    );
  }
  final manifest = BackupManifest(
    createdAtMs: (now ?? DateTime.now()).millisecondsSinceEpoch,
    projectJson: encodeProjectSnapshot(project),
    entries: entries,
  );
  final partial = File('$outPath.partial');
  try {
    await partial.parent.create(recursive: true);
    final sink = partial.openWrite();
    final body = utf8.encode(manifest.encode());
    final header = ByteData(8)
      ..setUint32(0, backupFormat)
      ..setUint32(4, body.length);
    sink
      ..add(ascii.encode(backupMagic))
      ..add(header.buffer.asUint8List())
      ..add(body);
    for (final entry in entries) {
      await sink.addStream(File(filePathOf(entry.uri)).openRead());
    }
    await sink.close();
    await partial.rename(outPath);
  } on FileSystemException catch (error) {
    await _discard(partial);
    throw BackupException(
      error.osError?.errorCode == _noSpaceErrno
          ? BackupFailure.storageFull
          : BackupFailure.io,
    );
  }
  return BackupResult(
    path: outPath,
    mediaCount: entries.length,
    missingCount: missing,
  );
}

Future<void> _discard(File file) async {
  try {
    if (file.existsSync()) await file.delete();
  } on FileSystemException {
    // A leftover partial file costs space only.
  }
}
