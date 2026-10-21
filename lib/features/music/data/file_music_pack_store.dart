import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cutter/features/music/data/pack_download.dart';
import 'package:cutter/features/music/data/unpack_zip.dart';
import 'package:cutter/features/music/domain/music_install_state.dart';
import 'package:cutter/features/music/domain/music_pack.dart';
import 'package:cutter/features/music/domain/music_ports.dart';

/// Unpacks a zip into a folder.
typedef PackUnpacker = Future<void> Function(String zipPath, String outDir);

/// Written last into a pack's folder, so a folder without it is a failed
/// install and is ignored.
const _installedName = 'installed.json';

/// Packs as folders under [root]: `<root>/<pack id>/` holds the tracks,
/// `pack.json` (their list) and `installed.json` (the catalog entry).
/// Everything is found by reading the disk, so it works offline and needs no
/// database.
class FileMusicPackStore implements MusicPackStore {
  /// Creates the store over [root], downloading with [download].
  FileMusicPackStore({
    required this.root,
    this.download = downloadWithHttpClient,
    this.unpack = unpackZip,
  });

  /// The folder that holds every pack.
  final Directory root;

  /// How a zip is fetched.
  final PackDownloader download;

  /// How a zip is unpacked.
  final PackUnpacker unpack;

  Directory get _scratch => Directory('${root.path}/.tmp');

  @override
  Future<List<InstalledPack>> installed() async {
    if (!root.existsSync()) return const [];
    final packs = <InstalledPack>[];
    await for (final entry in root.list()) {
      if (entry is! Directory || entry.path.split('/').last.startsWith('.')) {
        continue;
      }
      final pack = _read(entry);
      if (pack != null) packs.add(pack);
    }
    packs.sort((a, b) => a.pack.id.compareTo(b.pack.id));
    return packs;
  }

  InstalledPack? _read(Directory dir) {
    final marker = File('${dir.path}/$_installedName');
    final manifest = File('${dir.path}/$packManifestName');
    if (!marker.existsSync() || !manifest.existsSync()) return null;
    try {
      final pack = MusicPack.fromJson(
        (jsonDecode(marker.readAsStringSync()) as Map).cast<String, Object?>(),
      );
      final tracks = _tracksOf(manifest.readAsStringSync());
      return InstalledPack(
        pack: pack,
        directory: dir.path,
        tracks: tracks,
        sizeBytes: _sizeOf(dir),
      );
    } on Object {
      return null;
    }
  }

  int _sizeOf(Directory dir) => [
        for (final f in dir.listSync(recursive: true))
          if (f is File) f.lengthSync(),
      ].fold(0, (a, b) => a + b);

  List<MusicTrack> _tracksOf(String manifestJson) {
    final json = (jsonDecode(manifestJson) as Map).cast<String, Object?>();
    return [
      for (final t in json['tracks']! as List)
        MusicTrack.fromJson((t as Map).cast<String, Object?>()),
    ];
  }

  @override
  Future<InstalledPack> install(
    MusicPack pack, {
    required void Function(double? progress) onProgress,
    required void Function() onUnpacking,
    required TransferControl control,
  }) async {
    final work = Directory('${_scratch.path}/${pack.id}');
    final zip = File('${work.path}.zip');
    var keepZip = false;
    try {
      if (work.existsSync()) await work.delete(recursive: true);
      await work.create(recursive: true);
      // A partial file longer than the pack is from another version of it.
      if (pack.bytes > 0 && zip.existsSync() && zip.lengthSync() > pack.bytes) {
        await zip.delete();
      }

      final have = zip.existsSync() ? zip.lengthSync() : 0;
      if (pack.bytes == 0 || have != pack.bytes) {
        if (have > 0 && pack.bytes > 0) onProgress(have / pack.bytes);
        try {
          await download(
            Uri.parse(pack.url),
            zip,
            (received, total) =>
                onProgress(total > 0 ? received / total : null),
            control,
          );
        } on MusicTransferStopped catch (e) {
          keepZip = e.paused;
          rethrow;
        } on Object catch (e) {
          // Cut off: what arrived is kept, so retrying goes on from there.
          keepZip = true;
          throw MusicInstallException(MusicFailure.network, e);
        }
      }
      if (pack.bytes > 0 && zip.lengthSync() != pack.bytes) {
        throw const MusicInstallException(MusicFailure.corrupt, 'size');
      }

      onUnpacking();
      try {
        await unpack(zip.path, work.path);
      } on ArchiveException catch (e) {
        throw MusicInstallException(MusicFailure.corrupt, e);
      }

      final manifest = File('${work.path}/$packManifestName');
      if (!manifest.existsSync()) {
        throw const MusicInstallException(MusicFailure.corrupt, 'no manifest');
      }
      final tracks = _tracksOf(await manifest.readAsString());
      if (tracks.isEmpty ||
          tracks.any((t) => !File('${work.path}/${t.file}').existsSync())) {
        throw const MusicInstallException(MusicFailure.corrupt, 'tracks');
      }
      await File('${work.path}/$_installedName')
          .writeAsString(jsonEncode(pack.toJson()));

      // The folder is complete: swap it in, so a failure above never costs
      // the copy that was already there.
      final target = Directory('${root.path}/${pack.id}');
      if (target.existsSync()) await target.delete(recursive: true);
      await work.rename(target.path);
      return InstalledPack(
        pack: pack,
        directory: target.path,
        tracks: tracks,
        sizeBytes: _sizeOf(target),
      );
    } on FileSystemException catch (e) {
      throw MusicInstallException(MusicFailure.storage, e);
    } finally {
      if (!keepZip && zip.existsSync()) await zip.delete();
      if (work.existsSync()) await work.delete(recursive: true);
    }
  }

  @override
  Future<Map<String, int>> partials() async {
    if (!_scratch.existsSync()) return const {};
    return {
      await for (final f in _scratch.list())
        if (f is File && f.path.endsWith('.zip'))
          f.path.split('/').last.replaceAll(RegExp(r'\.zip$'), ''):
              f.lengthSync(),
    };
  }

  @override
  Future<void> discardPartial(String id) async {
    final zip = File('${_scratch.path}/$id.zip');
    if (zip.existsSync()) await zip.delete();
  }

  @override
  Future<void> remove(String id) async {
    final dir = Directory('${root.path}/$id');
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}
