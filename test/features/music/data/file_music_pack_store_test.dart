import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cutter/features/music/data/file_music_pack_store.dart';
import 'package:cutter/features/music/data/pack_download.dart';
import 'package:cutter/features/music/data/unpack_zip.dart';
import 'package:cutter/features/music/domain/music_install_state.dart';
import 'package:cutter/features/music/domain/music_pack.dart';
import 'package:cutter/features/music/domain/music_ports.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _zip(Map<String, List<int>> files) {
  final archive = Archive();
  files.forEach(
    (name, bytes) => archive.add(ArchiveFile(name, bytes.length, bytes)),
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _manifest(List<String> files) => jsonEncode({
      'tracks': [
        for (final f in files) {'file': f, 'title': f},
      ],
    });

MusicPack _pack(Uint8List zip, {String id = 'epic', int? bytes}) => MusicPack(
      id: id,
      names: const {'en': 'Epic'},
      genre: 'epic',
      source: const MusicSource(name: 'FreePD', license: 'CC0-1.0'),
      url: 'https://example.test/$id.zip',
      bytes: bytes ?? zip.length,
      trackCount: 1,
    );

PackDownloader _serving(Uint8List zip) =>
    (url, target, onProgress, control) async {
      await target.writeAsBytes(zip);
      onProgress(zip.length, zip.length);
    };

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('music_store_'));
  tearDown(() => root.deleteSync(recursive: true));

  FileMusicPackStore store(PackDownloader download) =>
      FileMusicPackStore(root: root, download: download);

  final good = _zip({
    'pack.json': utf8.encode(_manifest(['a.mp3'])),
    'a.mp3': [1, 2, 3],
  });

  test('installs a pack and finds it again from disk, offline', () async {
    final progress = <double?>[];
    var unpacking = 0;
    final installed = await store(_serving(good)).install(
      _pack(good),
      onProgress: progress.add,
      onUnpacking: () => unpacking++,
      control: TransferControl(),
    );

    expect(installed.tracks.single.file, 'a.mp3');
    final first = File(installed.pathOf(installed.tracks.single));
    expect(first.existsSync(), isTrue);
    expect(progress, [1.0]);
    expect(unpacking, 1);

    // A new store over the same folder, with no network at all.
    final again = await FileMusicPackStore(
      root: root,
      download: (_, __, ___, ____) => throw const SocketException('offline'),
    ).installed();
    expect(again.single.pack.id, 'epic');
    expect(again.single.tracks.single.title, 'a.mp3');
  });

  test('leaves no scratch files after an install', () async {
    await store(_serving(good)).install(
      _pack(good),
      onProgress: (_) {},
      onUnpacking: () {},
      control: TransferControl(),
    );
    final scratch = Directory('${root.path}/.tmp');
    final left =
        scratch.existsSync() ? scratch.listSync() : <FileSystemEntity>[];
    expect(left, isEmpty);
  });

  test('a download that fails is a network failure', () async {
    final s = store((_, __, ___, ____) => throw const SocketException('down'));
    await expectLater(
      s.install(
        _pack(good),
        onProgress: (_) {},
        onUnpacking: () {},
        control: TransferControl(),
      ),
      throwsA(
        isA<MusicInstallException>()
            .having((e) => e.failure, 'failure', MusicFailure.network),
      ),
    );
    expect(await s.installed(), isEmpty);
  });

  test('a zip of the wrong size is corrupt', () async {
    final s = store(_serving(good));
    await expectLater(
      s.install(
        _pack(good, bytes: good.length + 1),
        onProgress: (_) {},
        onUnpacking: () {},
        control: TransferControl(),
      ),
      throwsA(
        isA<MusicInstallException>()
            .having((e) => e.failure, 'failure', MusicFailure.corrupt),
      ),
    );
    expect(await s.installed(), isEmpty);
  });

  test('a zip that is not a zip is corrupt', () async {
    final junk = Uint8List.fromList(List.filled(64, 7));
    await expectLater(
      store(_serving(junk)).install(
        _pack(junk),
        onProgress: (_) {},
        onUnpacking: () {},
        control: TransferControl(),
      ),
      throwsA(
        isA<MusicInstallException>()
            .having((e) => e.failure, 'failure', MusicFailure.corrupt),
      ),
    );
  });

  test('a manifest that lists a missing track is corrupt', () async {
    final zip = _zip({
      'pack.json': utf8.encode(_manifest(['a.mp3', 'missing.mp3'])),
      'a.mp3': [1],
    });
    await expectLater(
      store(_serving(zip)).install(
        _pack(zip),
        onProgress: (_) {},
        onUnpacking: () {},
        control: TransferControl(),
      ),
      throwsA(isA<MusicInstallException>()),
    );
  });

  test('entries that leave the folder are refused', () async {
    final zip = _zip({
      'pack.json': utf8.encode(_manifest(['a.mp3'])),
      'a.mp3': [1],
      '../evil.mp3': [9],
    });
    await expectLater(
      store(_serving(zip)).install(
        _pack(zip),
        onProgress: (_) {},
        onUnpacking: () {},
        control: TransferControl(),
      ),
      throwsA(
        isA<MusicInstallException>()
            .having((e) => e.failure, 'failure', MusicFailure.corrupt),
      ),
    );
    expect(File('${root.path}/evil.mp3').existsSync(), isFalse);
  });

  test('a failed reinstall keeps the copy that was there', () async {
    final s = store(_serving(good));
    await s.install(
      _pack(good),
      onProgress: (_) {},
      onUnpacking: () {},
      control: TransferControl(),
    );
    final broken =
        store((_, __, ___, ____) => throw const SocketException('down'));
    await expectLater(
      broken.install(
        _pack(good),
        onProgress: (_) {},
        onUnpacking: () {},
        control: TransferControl(),
      ),
      throwsA(isA<MusicInstallException>()),
    );
    expect((await s.installed()).single.pack.id, 'epic');
  });

  test('a folder without the completion marker is not a pack', () async {
    Directory('${root.path}/half').createSync(recursive: true);
    File('${root.path}/half/pack.json').writeAsStringSync(_manifest(['a.mp3']));
    expect(await store(_serving(good)).installed(), isEmpty);
  });

  test('remove deletes the pack', () async {
    final s = store(_serving(good));
    await s.install(
      _pack(good),
      onProgress: (_) {},
      onUnpacking: () {},
      control: TransferControl(),
    );
    await s.remove('epic');
    expect(await s.installed(), isEmpty);
  });

  group('pause, resume and cancel', () {
    // A downloader that serves [zip] in two halves: the first call writes the
    // first half and then stops as asked; a later call appends the rest.
    PackDownloader halves(Uint8List zip, {void Function()? beforeStop}) {
      return (url, target, onProgress, control) async {
        final have = target.existsSync() ? target.lengthSync() : 0;
        final half = zip.length ~/ 2;
        if (have == 0) {
          await target.writeAsBytes(zip.sublist(0, half));
          onProgress(half, zip.length);
          beforeStop?.call();
          await control.whenStopped;
          throw MusicTransferStopped(paused: !control.cancelled);
        }
        await target.writeAsBytes(zip.sublist(have), mode: FileMode.append);
        onProgress(zip.length, zip.length);
      };
    }

    test('a paused download is kept and resumed from where it stopped',
        () async {
      final big = _zip({
        'pack.json': utf8.encode(_manifest(['a.mp3'])),
        'a.mp3': List.generate(2000, (i) => (i * 37) % 251),
      });
      final control = TransferControl();
      final s = store(halves(big, beforeStop: control.pause));

      await expectLater(
        s.install(
          _pack(big),
          onProgress: (_) {},
          onUnpacking: () {},
          control: control,
        ),
        throwsA(
          isA<MusicTransferStopped>().having((e) => e.paused, 'paused', true),
        ),
      );
      expect((await s.partials())['epic'], big.length ~/ 2);
      expect(await s.installed(), isEmpty);

      final progress = <double?>[];
      final done = await s.install(
        _pack(big),
        onProgress: progress.add,
        onUnpacking: () {},
        control: TransferControl(),
      );
      expect(progress.first, closeTo(0.5, 0.01));
      expect(done.tracks.single.file, 'a.mp3');
      expect(await s.partials(), isEmpty);
    });

    test('a cancelled download leaves nothing', () async {
      final control = TransferControl();
      final s = store(halves(good, beforeStop: control.cancel));

      await expectLater(
        s.install(
          _pack(good),
          onProgress: (_) {},
          onUnpacking: () {},
          control: control,
        ),
        throwsA(
          isA<MusicTransferStopped>().having((e) => e.paused, 'paused', false),
        ),
      );
      expect(await s.partials(), isEmpty);
    });

    test('a connection that drops keeps what arrived', () async {
      final s = store((url, target, onProgress, control) async {
        await target.writeAsBytes(good.sublist(0, 10));
        throw const SocketException('reset');
      });
      await expectLater(
        s.install(
          _pack(good),
          onProgress: (_) {},
          onUnpacking: () {},
          control: TransferControl(),
        ),
        throwsA(isA<MusicInstallException>()),
      );
      expect((await s.partials())['epic'], 10);
    });

    test('discardPartial deletes what was kept', () async {
      Directory('${root.path}/.tmp').createSync(recursive: true);
      File('${root.path}/.tmp/epic.zip').writeAsBytesSync([1, 2, 3]);
      final s = store(_serving(good));
      expect((await s.partials())['epic'], 3);

      await s.discardPartial('epic');

      expect(await s.partials(), isEmpty);
    });

    test('the installed size counts the files on disk', () async {
      final s = store(_serving(good));
      final done = await s.install(
        _pack(good),
        onProgress: (_) {},
        onUnpacking: () {},
        control: TransferControl(),
      );
      expect(done.sizeBytes, greaterThan(3));
      expect((await s.installed()).single.sizeBytes, done.sizeBytes);
    });
  });

  group('isAllowedEntry', () {
    test('accepts sounds and the manifest by relative paths', () {
      expect(isAllowedEntry('pack.json'), isTrue);
      expect(isAllowedEntry('a.MP3'), isTrue);
      expect(isAllowedEntry('sub/a.ogg'), isTrue);
    });

    test('refuses anything else', () {
      for (final name in [
        '../a.mp3',
        '/a.mp3',
        'a/../b.mp3',
        r'a\b.mp3',
        'run.sh',
        'a.mp3.exe',
        'noext',
        '',
      ]) {
        expect(isAllowedEntry(name), isFalse, reason: name);
      }
    });
  });
}
