// Builds the music packs the app downloads, and their catalog.
//
//   dart run tool/music_packs/build_packs.dart --out build/music_packs
//   (--sources <file> reads another list; --only <pack>; --limit <tracks>)
//
// Reads sources.json next to this file, downloads each track from its source,
// re-encodes it to a small MP3 with ffmpeg, writes one zip per pack
// (`<id>.zip` holding the tracks and a `pack.json`) and a `catalog.json`.
// Upload the whole output folder to the host `baseUrl` points at, and give the
// app the catalog's URL with MUSIC_CATALOG_URL.
//
// Only sources whose licence is on `allowedLicenses` are built. Check each
// source's terms before publishing: this script does not do it for you.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

Future<void> main(List<String> args) async {
  final out = Directory(_option(args, '--out') ?? 'build/music_packs')
    ..createSync(recursive: true);
  final only = _option(args, '--only');
  final limit = int.tryParse(_option(args, '--limit') ?? '');
  final config = jsonDecode(
    File(
      _option(args, '--sources') ??
          '${File.fromUri(Platform.script).parent.path}/sources.json',
    ).readAsStringSync(),
  ) as Map<String, dynamic>;
  final allowed = (config['allowedLicenses'] as List).cast<String>().toSet();
  final bitrate = config['bitrateKbps'] as int;
  final baseUrl = (config['baseUrl'] as String).replaceAll(RegExp(r'/$'), '');

  await _need('ffmpeg');
  await _need('ffprobe');

  final packs = <_Pack>[];
  for (final item
      in (config['archiveItems'] as List).cast<Map<String, dynamic>>()) {
    final source = item['source'] as Map<String, dynamic>;
    _checkLicense(source, allowed);
    packs.addAll(await _archiveItemPacks(item.cast<String, dynamic>(), source));
  }
  for (final t
      in (config['directTracks'] as List).cast<Map<String, dynamic>>()) {
    final source = t['source'] as Map<String, dynamic>;
    _checkLicense(source, allowed);
    final pack = packs.firstWhere(
      (p) => p.id == t['pack'],
      orElse: () {
        final p = _Pack(
          id: t['pack'] as String,
          genre: t['genre'] as String,
          names: (t['names'] as Map).cast<String, String>(),
          source: source,
        );
        packs.add(p);
        return p;
      },
    );
    pack.remote.add(
      _Remote(
        url: t['url'] as String,
        file: t['file'] as String,
        title: t['title'] as String,
        artist: t['artist'] as String?,
      ),
    );
  }

  final catalog = <Map<String, Object?>>[];
  for (final pack in packs) {
    if (only != null && pack.id != only) continue;
    final entry = await _build(pack, out, bitrate, baseUrl, limit);
    if (entry != null) catalog.add(entry);
  }
  File('${out.path}/catalog.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ')
        .convert({'version': 1, 'packs': catalog}),
  );
  stdout.writeln('Done: ${catalog.length} packs in ${out.path}');
}

String? _option(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

Future<void> _need(String tool) async {
  final r = await Process.run('which', [tool]);
  if (r.exitCode != 0) {
    stderr.writeln('$tool is needed on the PATH.');
    exit(1);
  }
}

void _checkLicense(Map<String, dynamic> source, Set<String> allowed) {
  if (!allowed.contains(source['license'])) {
    stderr.writeln('Licence ${source['license']} of ${source['name']} is '
        'not on allowedLicenses.');
    exit(1);
  }
}

class _Remote {
  _Remote({
    required this.url,
    required this.file,
    required this.title,
    this.fallbackUrl,
    this.artist,
  });

  final String url;

  /// Tried when [url] fails.
  final String? fallbackUrl;
  final String file;
  final String title;
  final String? artist;
}

class _Pack {
  _Pack({
    required this.id,
    required this.genre,
    required this.names,
    required this.source,
  });

  final String id;
  final String genre;
  final Map<String, String> names;
  final Map<String, dynamic> source;
  final List<_Remote> remote = [];
}

/// Lists an archive.org item and groups its MP3s into packs by folder.
Future<List<_Pack>> _archiveItemPacks(
  Map<String, dynamic> item,
  Map<String, dynamic> source,
) async {
  final id = item['identifier'] as String;
  final meta = jsonDecode(await _get('https://archive.org/metadata/$id'))
      as Map<String, dynamic>;
  // The item's own server: the generic download redirect sometimes lands on a
  // mirror that answers 500.
  final host = 'https://${meta['d1']}${meta['dir']}';
  final folders = item['folders'] as Map<String, dynamic>;
  final packs = {
    for (final e in folders.entries)
      e.key: _Pack(
        id: (e.value as Map<String, dynamic>)['id'] as String,
        genre: (e.value as Map<String, dynamic>)['genre'] as String,
        names: ((e.value as Map<String, dynamic>)['names'] as Map)
            .cast<String, String>(),
        source: source,
      ),
  };
  for (final f in (meta['files'] as List).cast<Map<String, dynamic>>()) {
    final name = f['name'] as String;
    if (!name.toLowerCase().endsWith('.mp3') || !name.contains('/')) continue;
    final pack = packs[name.split('/').first];
    if (pack == null) continue;
    final base = name.split('/').last;
    pack.remote.add(
      _Remote(
        url: 'https://archive.org/download/$id/${Uri.encodeFull(name)}',
        fallbackUrl: '$host/${Uri.encodeFull(name)}',
        file: '${_slug(base.substring(0, base.length - 4))}.mp3',
        title: base.substring(0, base.length - 4),
        artist: source['name'] as String?,
      ),
    );
  }
  return packs.values.where((p) => p.remote.isNotEmpty).toList();
}

String _slug(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+\$'), '');

Future<String> _get(String url) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

Future<void> _download(List<String> urls, File target) async {
  for (var attempt = 1;; attempt++) {
    try {
      await _downloadOnce(urls[(attempt - 1) % urls.length], target);
      return;
    } on Object {
      if (attempt == 4) rethrow;
      await Future<void>.delayed(Duration(seconds: 2 * attempt));
    }
  }
}

Future<void> _downloadOnce(String url, File target) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    final sink = target.openWrite();
    await response.pipe(sink);
  } finally {
    client.close();
  }
}

Future<Map<String, Object?>?> _build(
  _Pack pack,
  Directory out,
  int bitrate,
  String baseUrl,
  int? limit,
) async {
  stdout.writeln('Pack ${pack.id}: ${pack.remote.length} tracks');
  final work = Directory('${out.path}/.work/${pack.id}')
    ..createSync(recursive: true);
  final tracks = <Map<String, Object?>>[];
  final used = <String>{};
  for (final r in pack.remote.take(limit ?? pack.remote.length)) {
    if (!used.add(r.file)) continue;
    final raw = File('${work.path}/raw-${r.file}');
    final encoded = File('${work.path}/${r.file}');
    try {
      await _download([r.url, if (r.fallbackUrl != null) r.fallbackUrl!], raw);
      final ff = await Process.run('ffmpeg', [
        '-y', '-v', 'error', '-i', raw.path, '-vn', '-map_metadata', '-1',
        '-ac', '2', '-ar', '44100', '-b:a', '${bitrate}k', encoded.path, //
      ]);
      if (ff.exitCode != 0) throw StateError('${ff.stderr}');
    } on Object catch (e) {
      stderr.writeln('  skipped ${r.title}: $e');
      continue;
    } finally {
      if (raw.existsSync()) raw.deleteSync();
    }
    final probe = await Process.run('ffprobe', [
      '-v', 'error', '-show_entries', 'format=duration', '-of', //
      'default=nw=1:nk=1', encoded.path, //
    ]);
    final seconds = double.tryParse('${probe.stdout}'.trim()) ?? 0;
    tracks.add({
      'file': r.file,
      'title': r.title,
      'artist': r.artist,
      'durationMs': (seconds * 1000).round(),
    });
  }
  if (tracks.isEmpty) return null;
  File('${work.path}/pack.json')
      .writeAsStringSync(jsonEncode({'tracks': tracks}));

  final zip = File('${out.path}/${pack.id}.zip');
  final encoder = ZipFileEncoder()..create(zip.path);
  await encoder.addFile(File('${work.path}/pack.json'), 'pack.json');
  for (final t in tracks) {
    await encoder.addFile(
      File('${work.path}/${t['file']}'),
      t['file']! as String,
    );
  }
  await encoder.close();
  work.deleteSync(recursive: true);

  return {
    'id': pack.id,
    'names': pack.names,
    'genre': pack.genre,
    'source': pack.source,
    'url': '$baseUrl/${pack.id}.zip',
    'bytes': zip.lengthSync(),
    'trackCount': tracks.length,
  };
}
