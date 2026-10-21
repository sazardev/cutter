import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';

/// Sound formats a pack may hold.
const _soundExtensions = {'mp3', 'm4a', 'aac', 'ogg', 'opus', 'wav', 'flac'};

/// The file inside every pack that lists its tracks.
const packManifestName = 'pack.json';

/// Whether an entry of a pack's zip may be written: a sound or the manifest,
/// by a relative path that stays inside the folder.
bool isAllowedEntry(String name) {
  if (name.contains(r'\') || name.startsWith('/') || name.contains('\x00')) {
    return false;
  }
  final parts = name.split('/');
  if (parts.any((p) => p.isEmpty || p == '.' || p == '..')) return false;
  if (name == packManifestName) return true;
  final dot = name.lastIndexOf('.');
  return dot > 0 &&
      _soundExtensions.contains(name.substring(dot + 1).toLowerCase());
}

/// Unpacks the zip at [zipPath] into [outDir] off the UI thread, checking
/// each entry's CRC. Entries that are not sounds or the manifest, or whose
/// path leaves [outDir], are refused: a pack is data from the network.
Future<void> unpackZip(String zipPath, String outDir) =>
    Isolate.run(() => _unpackSync(zipPath, outDir));

void _unpackSync(String zipPath, String outDir) {
  final input = InputFileStream(zipPath);
  try {
    final archive = ZipDecoder().decodeStream(input, verify: true);
    for (final entry in archive) {
      if (!entry.isFile) continue;
      if (!isAllowedEntry(entry.name)) {
        throw ArchiveException('Entry not allowed: ${entry.name}');
      }
      final file = File('$outDir/${entry.name}')
        ..parent.createSync(recursive: true);
      final output = OutputFileStream(file.path);
      try {
        entry.writeContent(output);
      } finally {
        output.closeSync();
      }
    }
  } finally {
    input.closeSync();
  }
}
