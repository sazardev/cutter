import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
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
  var stall = false;
  int? rangeStart;
  final release = Completer<void>();

  Future<void> serveZip(HttpRequest request) async {
    final response = request.response;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    var start = 0;
    if (range != null) {
      start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      rangeStart = start;
      response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-${zip.length - 1}/${zip.length}',
        );
    }
    response.headers.contentLength = zip.length - start;
    try {
      if (stall && start == 0) {
        final half = zip.length ~/ 2;
        response.add(zip.sublist(0, half));
        await response.flush();
        await Future.any([
          release.future,
          Future<void>.delayed(const Duration(seconds: 10)),
        ]);
        response.add(zip.sublist(half));
      } else {
        response.add(zip.sublist(start));
      }
      await response.close();
    } on Object {
      // The client hung up (a pause); nothing to do.
    }
  }

  setUp(() async {
    // flutter_test answers every request with 400 unless this is cleared.
    HttpOverrides.global = null;
    root = Directory.systemTemp.createTempSync('music_http_');
    final noise = Random(1);
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
      ..add(
        ArchiveFile.bytes(
          'one.mp3',
          List.generate(200000, (_) => noise.nextInt(256)),
        ),
      );
    zip = Uint8List.fromList(ZipEncoder().encode(archive));
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest request) {
      final path = request.uri.path;
      if (failNext) {
        failNext = false;
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..close();
      } else if (path == '/demo.zip') {
        serveZip(request);
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
      control: TransferControl(),
    );

    expect(progress.last, 1.0);
    expect(installed.tracks.single.title, 'One');
    expect(
      File(installed.pathOf(installed.tracks.single)).lengthSync(),
      200000,
    );
  });

  test('a download paused over HTTP resumes with a Range request', () async {
    final json =
        jsonDecode(_catalog(server.port, zip.length)) as Map<String, Object?>;
    final pack = MusicPack.fromJson(
      ((json['packs']! as List).first as Map).cast<String, Object?>(),
    );
    final store = FileMusicPackStore(root: root);
    stall = true;
    final control = TransferControl();

    final first = store.install(
      pack,
      onProgress: (p) {
        // The first half has arrived: pause there.
        if (p != null && p >= 0.45) control.pause();
      },
      onUnpacking: () {},
      control: control,
    );
    await expectLater(
      first,
      throwsA(
        isA<MusicTransferStopped>().having((e) => e.paused, 'paused', true),
      ),
    );
    final kept = (await store.partials())['demo']!;
    expect(kept, greaterThan(0));
    expect(kept, lessThan(zip.length));
    expect(await store.installed(), isEmpty);

    stall = false;
    final progress = <double?>[];
    final done = await store.install(
      pack,
      onProgress: progress.add,
      onUnpacking: () {},
      control: TransferControl(),
    );

    expect(rangeStart, kept);
    expect(progress.first, closeTo(kept / zip.length, 0.01));
    expect(File(done.pathOf(done.tracks.single)).lengthSync(), 200000);
    expect(await store.partials(), isEmpty);
    release.complete();
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
      store.install(
        pack,
        onProgress: (_) {},
        onUnpacking: () {},
        control: TransferControl(),
      ),
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
