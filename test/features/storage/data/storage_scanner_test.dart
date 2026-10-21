import 'dart:io';

import 'package:cutter/features/storage/data/storage_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory sandbox;
  late Directory media;
  late Directory cache;

  File write(Directory dir, String name, int bytes) =>
      File('${dir.path}/$name')..writeAsBytesSync(List.filled(bytes, 1));

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('cutter_storage_test');
    media = Directory('${sandbox.path}/media')..createSync();
    cache = Directory('${sandbox.path}/cache')..createSync();
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  test('measures media, cache, unused files and each project', () {
    final a = write(media, 'a.mp4', 1000);
    final b = write(media, 'b.mp4', 400);
    final shared = write(media, 'shared.mp4', 100);
    final orphan = write(media, 'orphan.mp4', 50);
    write(cache, 'tmp.bin', 30);

    final report = scanStorage(
      mediaRoot: media,
      cacheDir: cache,
      exportBytes: 777,
      projects: [
        ProjectMedia(
          id: 'p1',
          name: 'Trip',
          paths: {a.path, shared.path, '/elsewhere/not-ours.mp4'},
        ),
        ProjectMedia(
          id: 'p2',
          name: 'Old',
          paths: {b.path, shared.path},
          trashed: true,
        ),
      ],
    );

    expect(report.mediaBytes, 1550);
    expect(report.cacheBytes, 30);
    expect(report.exportBytes, 777);
    expect(report.totalBytes, 1550 + 30 + 777);
    expect(report.unusedPaths, [orphan.path]);
    expect(report.unusedBytes, 50);

    // The biggest first; files outside the app's folder cost nothing here.
    expect(report.projects.map((p) => p.name), ['Trip', 'Old']);
    expect(report.projects.first.bytes, 1100);
    expect(report.projects.first.sharedBytes, 100);
    expect(report.projects.last.bytes, 500);
    expect(report.projects.last.trashed, isTrue);
  });

  test('missing folders are simply empty', () {
    final report = scanStorage(
      mediaRoot: Directory('${sandbox.path}/nope'),
      cacheDir: Directory('${sandbox.path}/nada'),
      projects: const [],
      exportBytes: 0,
    );

    expect(report.totalBytes, 0);
    expect(report.unusedPaths, isEmpty);
  });

  test('the cache keeps recent files and removes the old ones', () {
    final old = write(cache, 'old.bin', 40);
    final fresh = write(cache, 'fresh.bin', 60);
    old.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 2)));

    final freed = clearCache(cache);

    expect(freed, 40);
    expect(old.existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue);
    expect(cache.existsSync(), isTrue);
  });

  test('deleting unused media never leaves the media folder', () {
    final inside = write(media, 'orphan.mp4', 70);
    final outside = write(sandbox, 'precious.mp4', 90);

    final freed = deleteMediaFiles(media, [inside.path, outside.path]);

    expect(freed, 70);
    expect(inside.existsSync(), isFalse);
    expect(outside.existsSync(), isTrue);
  });
}
