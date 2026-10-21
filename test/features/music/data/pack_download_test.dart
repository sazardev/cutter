import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cutter/features/music/data/file_music_pack_store.dart';
import 'package:cutter/features/music/data/http_music_catalog.dart';
import 'package:cutter/features/music/domain/music_install_state.dart';
import 'package:cutter/features/music/domain/music_pack.dart';
import 'package:cutter/features/music/domain/music_ports.dart';
import 'package:flutter_test/flutter_test.dart';

/// The real downloader, unpacker (in an isolate) and catalog fetcher against
/// a local HTTP server, so what the app does on a phone is exercised without
/// the internet.
void main() {
  late HttpServer server;
  late Directory root;
  late Uint8List zip;
  var failNext = false;

  setUp(() async {
    // flutter_test answers every request with 400 unless this is cleared.
    HttpOverrides.global = null;
    root = Directory.systemTemp.createTempSync('music_http_');
    final archive = Archive()
      ..add(
        ArchiveFile.bytes(
          'pack.json',
          utf8.encode(
            jsonEncode({
              'tracks': [
                {'file': 'one.mp3', 'title': 'One', 'durationMs': 2000},
              ],
            }),
          ),
        ),
      )
      ..add(ArchiveFile.bytes('one.mp3', List.filled(4096, 5)));
    zip = Uint8List.fromList(ZipEncoder().encode(archive));
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      final path = request.uri.path;
      if (failNext) {
        failNext = false;
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..close();
      } else if (path == '/demo.zip') {
        request.response
          ..headers.contentLength = zip.length
          ..add(zip)
          ..close();
      } else if (path == '/catalog.json') {
        request.response
          ..write(_catalog(server.port, zip.length))
          ..close();
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
      }
    });
  });

  tearDown(() async {
    await server.close(force: true);
    root.deleteSync(recursive: true);
  });

  test('catalog, download and unpack work over real HTTP', () async {
    final catalog = HttpMusicCatalog(
      url: 'http://127.0.0.1:${server.port}/catalog.json',
      cache: File('${root.path}/.catalog.json'),
    );
    final packs = (await catalog.load())!;
    expect(packs.single.id, 'demo');

    final progress = <double?>[];
    final installed = await FileMusicPackStore(root: root).install(
      packs.single,
      onProgress: progress.add,
      onUnpacking: () {},
    );

    expect(progress.last, 1.0);
    expect(installed.tracks.single.title, 'One');
    expect(
      File(installed.pathOf(installed.tracks.single)).lengthSync(),
      4096,
    );
  });

  test('an HTTP error is a network failure and leaves nothing', () async {
    final json =
        jsonDecode(_catalog(server.port, zip.length)) as Map<String, Object?>;
    final pack = MusicPack.fromJson(
      ((json['packs']! as List).first as Map).cast<String, Object?>(),
    );
    failNext = true;
    final store = FileMusicPackStore(root: root);

    await expectLater(
      store.install(pack, onProgress: (_) {}, onUnpacking: () {}),
      throwsA(
        isA<MusicInstallException>()
            .having((e) => e.failure, 'failure', MusicFailure.network),
      ),
    );
    expect(await store.installed(), isEmpty);
  });
}

String _catalog(int port, int bytes) => jsonEncode({
      'version': 1,
      'packs': [
        {
          'id': 'demo',
          'names': {'en': 'Demo'},
          'genre': 'upbeat',
          'source': {'name': 'Local', 'license': 'CC0-1.0'},
          'url': 'http://127.0.0.1:$port/demo.zip',
          'bytes': bytes,
          'trackCount': 1,
        },
      ],
    });
