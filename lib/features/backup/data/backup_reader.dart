import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cutter/features/backup/domain/backup_format.dart';
import 'package:cutter/features/editor/data/project_snapshot_codec.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/project.dart';

// errno of "no space left on device" on Linux and Android.
const int _noSpaceErrno = 28;
const int _chunk = 1024 * 1024;
const int _headerBytes = 16;

/// Unpacks the backup at [path]: the media files are written into [mediaRoot]
/// and the project comes back with new ids (so it never clashes with the
/// original) and its clips pointing at the unpacked copies. Clips whose file
/// was not in the backup keep their old source and show as missing.
///
/// Throws [BackupException]; whatever was unpacked before a failure is
/// removed.
Future<Project> readBackup(
  String path, {
  required Directory mediaRoot,
  required IdGenerator ids,
  String? restoredName,
}) async {
  final file = File(path);
  if (!file.existsSync()) throw const BackupException(BackupFailure.io);
  final written = <File>[];
  RandomAccessFile? input;
  try {
    input = await file.open();
    final length = await input.length();
    final header = await _read(input, _headerBytes);
    if (header.length < _headerBytes ||
        ascii.decode(header.sublist(0, 8), allowInvalid: true) != backupMagic) {
      throw const BackupException(BackupFailure.notABackup);
    }
    final view = ByteData.sublistView(header);
    if (view.getUint32(8) > backupFormat) {
      throw const BackupException(BackupFailure.newerVersion);
    }
    final manifestLength = view.getUint32(12);
    if (manifestLength > length - _headerBytes) {
      throw const BackupException(BackupFailure.damaged);
    }
    final BackupManifest manifest;
    try {
      manifest = BackupManifest.decode(
        utf8.decode(await _read(input, manifestLength)),
      );
    } on Object {
      // Not valid text or not the expected shape: a damaged manifest.
      throw const BackupException(BackupFailure.damaged);
    }
    if (_headerBytes + manifestLength + manifest.mediaBytes != length) {
      throw const BackupException(BackupFailure.damaged);
    }

    await mediaRoot.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final moved = <String, String>{};
    for (var i = 0; i < manifest.entries.length; i++) {
      final entry = manifest.entries[i];
      final target = File(
        '${mediaRoot.path}${Platform.pathSeparator}'
        '${stamp}_${i}_${_safe(entry.name)}',
      );
      written.add(target);
      final sink = target.openWrite();
      var left = entry.size;
      while (left > 0) {
        final bytes = await _read(input, left < _chunk ? left : _chunk);
        if (bytes.isEmpty) {
          await sink.close();
          throw const BackupException(BackupFailure.damaged);
        }
        sink.add(bytes);
        left -= bytes.length;
      }
      await sink.close();
      moved[entry.uri] = target.path;
    }

    return _remapped(
      decodeProjectSnapshot(manifest.projectJson),
      moved,
      ids,
      restoredName,
    );
  } on BackupException {
    await _discardAll(written);
    rethrow;
  } on FileSystemException catch (error) {
    await _discardAll(written);
    throw BackupException(
      error.osError?.errorCode == _noSpaceErrno
          ? BackupFailure.storageFull
          : BackupFailure.io,
    );
  } finally {
    await input?.close();
  }
}

Future<Uint8List> _read(RandomAccessFile input, int count) => input.read(count);

String _safe(String name) => name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

Project _remapped(
  Project project,
  Map<String, String> moved,
  IdGenerator ids,
  String? name,
) {
  return Project(
    id: ids.next(),
    name: name ?? project.name,
    templateId: project.templateId,
    canvas: project.canvas,
    layers: [
      for (final layer in project.layers)
        () {
          final layerId = ids.next();
          return Layer(
            id: layerId,
            name: layer.name,
            kind: layer.kind,
            volume: layer.volume,
            muted: layer.muted,
            clips: [
              for (final Clip clip in layer.clips)
                clip.copyWith(
                  id: ids.next(),
                  layerId: layerId,
                  sourceUri: moved[clip.sourceUri],
                ),
            ],
          );
        }(),
    ],
  );
}

Future<void> _discardAll(List<File> files) async {
  for (final file in files) {
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // A leftover costs space only.
    }
  }
}
