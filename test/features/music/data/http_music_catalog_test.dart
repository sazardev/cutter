import 'dart:convert';
import 'dart:io';

import 'package:cutter/features/music/data/http_music_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

String _catalog(String id) => jsonEncode({
      'version': 1,
      'packs': [
        {
          'id': id,
          'names': {'en': 'Epic', 'es': 'Épica'},
          'genre': 'epic',
          'source': {'name': 'FreePD', 'license': 'CC0-1.0'},
          'url': 'https://example.test/$id.zip',
          'bytes': 10,
          'trackCount': 2,
        },
      ],
    });

void main() {
  late Directory dir;
  late File cache;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('music_catalog_');
    cache = File('${dir.path}/catalog.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('loads from the network and keeps a copy', () async {
    final catalog = HttpMusicCatalog(
      url: 'https://example.test/catalog.json',
      cache: cache,
      fetch: (_) async => _catalog('epic'),
    );
    final packs = await catalog.load();
    expect(packs!.single.nameIn('es'), 'Épica');
    expect(packs.single.nameIn('fr'), 'Epic');
    expect(cache.existsSync(), isTrue);
  });

  test('offline it serves the last copy', () async {
    cache.writeAsStringSync(_catalog('cached'));
    final catalog = HttpMusicCatalog(
      url: 'https://example.test/catalog.json',
      cache: cache,
      fetch: (_) => throw const SocketException('offline'),
    );
    expect((await catalog.load())!.single.id, 'cached');
  });

  test('a broken answer does not replace the copy', () async {
    cache.writeAsStringSync(_catalog('cached'));
    final catalog = HttpMusicCatalog(
      url: 'https://example.test/catalog.json',
      cache: cache,
      fetch: (_) async => '{"version": 2}',
    );
    expect((await catalog.load())!.single.id, 'cached');
    expect(cache.readAsStringSync(), _catalog('cached'));
  });

  test('is null with no network and no copy', () async {
    final catalog = HttpMusicCatalog(
      url: '',
      cache: cache,
      fetch: (_) => throw StateError('never called'),
    );
    expect(await catalog.load(), isNull);
  });
}
