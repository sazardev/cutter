import 'dart:convert';
import 'dart:io';

import 'package:cutter/features/music/domain/music_pack.dart';
import 'package:cutter/features/music/domain/music_ports.dart';

/// Fetches the JSON of a catalog.
typedef CatalogFetcher = Future<String> Function(Uri url);

/// The fetcher the app uses.
Future<String> fetchWithHttpClient(Uri url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(url);
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

/// The catalog at [url], with the last good copy kept in [cache] for when
/// the device is offline.
class HttpMusicCatalog implements MusicCatalog {
  /// Creates the catalog.
  HttpMusicCatalog({
    required this.url,
    required this.cache,
    this.fetch = fetchWithHttpClient,
  });

  /// Where the catalog is; empty when the build has none configured.
  final String url;

  /// The file that keeps the last copy.
  final File cache;

  /// How the JSON is fetched.
  final CatalogFetcher fetch;

  @override
  Future<List<MusicPack>?> load() async {
    if (url.isNotEmpty) {
      try {
        final body = await fetch(Uri.parse(url));
        final packs = parseCatalog(body);
        await cache.parent.create(recursive: true);
        await cache.writeAsString(body);
        return packs;
      } on Object {
        // Offline or a broken answer: fall back to the copy.
      }
    }
    if (!cache.existsSync()) return null;
    try {
      return parseCatalog(cache.readAsStringSync());
    } on Object {
      return null;
    }
  }
}

/// Parses the catalog JSON: `{"version": 1, "packs": [...]}`. Throws on a
/// shape it does not know, so a bad answer never replaces a good copy.
List<MusicPack> parseCatalog(String body) {
  final json = (jsonDecode(body) as Map).cast<String, Object?>();
  if (json['version'] != 1) throw const FormatException('catalog version');
  return [
    for (final p in json['packs']! as List)
      MusicPack.fromJson((p as Map).cast<String, Object?>()),
  ];
}
