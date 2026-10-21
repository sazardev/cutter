import 'dart:io';

import 'package:cutter/features/editor/data/media_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory sandbox;
  late Directory cache;
  late Directory library;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('cutter_media_test');
    cache = Directory('${sandbox.path}/cache')..createSync();
    library = Directory('${sandbox.path}/library');
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  File source(String dir, String name, {String text = 'video'}) =>
      File('$dir/$name')..writeAsStringSync(text);

  test('a file outside the app is copied and the original stays', () async {
    final original = source(sandbox.path, 'trip.mp4');
    final media = MediaLibrary(root: library, volatileRoots: [cache.path]);

    final kept = await media.keep(original.path);

    expect(kept, startsWith(library.path));
    expect(File(kept).readAsStringSync(), 'video');
    expect(original.existsSync(), isTrue);
    expect(media.contains(kept), isTrue);
  });

  test('a file the picker left in the cache is moved, not duplicated',
      () async {
    final picked = source(cache.path, 'clip.mp4');
    final media = MediaLibrary(root: library, volatileRoots: [cache.path]);

    final kept = await media.keep(picked.path);

    expect(kept, startsWith(library.path));
    expect(picked.existsSync(), isFalse);
    expect(File(kept).existsSync(), isTrue);
  });

  test('a file already in the library is left where it is', () async {
    final media = MediaLibrary(root: library, volatileRoots: [cache.path]);
    library.createSync();
    final inside = source(library.path, 'already.mp4');

    expect(await media.keep(inside.path), inside.path);
    expect(library.listSync(), hasLength(1));
  });

  test('a missing file fails cleanly and leaves nothing behind', () async {
    final media = MediaLibrary(root: library, volatileRoots: [cache.path]);

    await expectLater(
      media.keep('${sandbox.path}/gone.mp4'),
      throwsA(isA<MediaCopyFailed>()),
    );
    expect(library.listSync(), isEmpty);
  });

  test('a full disk is reported as such and the partial copy is removed',
      () async {
    final original = source(sandbox.path, 'big.mp4');
    final media = MediaLibrary(
      root: library,
      volatileRoots: [cache.path],
      copier: (from, to) async {
        File(to).writeAsStringSync('half');
        throw FileSystemException(
          'write failed',
          to,
          const OSError('No space left on device', 28),
        );
      },
    );

    await expectLater(
      media.keep(original.path),
      throwsA(isA<MediaStorageFull>()),
    );
    expect(library.listSync(), isEmpty);
    expect(original.existsSync(), isTrue);
  });
}
