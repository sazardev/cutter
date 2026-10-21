import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/features/editor/data/drift_media_bank.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/media_bank.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

MediaItem _item(String id, String project, String path, int at) => MediaItem(
      id: id,
      projectId: project,
      path: path,
      kind: MediaKind.video,
      durationMs: 1000,
      addedAtMs: at,
    );

void main() {
  late AppDatabase db;
  late Set<String> files;
  late DriftMediaBank bank;

  setUp(() async {
    db = AppDatabase.inMemory();
    for (final id in ['p1', 'p2']) {
      await db.into(db.editorProjects).insert(
            EditorProjectsCompanion.insert(
              id: id,
              name: id,
              createdAtMs: 0,
              updatedAtMs: 0,
              canvasWidth: 1080,
              canvasHeight: 1920,
              fps: 30,
              savedAtMs: const Value(null),
            ),
          );
    }
    files = {'/a.mp4', '/b.mp4', '/c.mp4'};
    bank = DriftMediaBank(db, exists: files.contains);
  });

  tearDown(() => db.close());

  test('a project bank lists its files, newest first, each once', () async {
    await bank.add([
      _item('1', 'p1', '/a.mp4', 1),
      _item('2', 'p1', '/b.mp4', 2),
      _item('3', 'p1', '/a.mp4', 3),
    ]);

    final items = await bank.itemsOf('p1');
    expect(items.map((i) => i.path), ['/b.mp4', '/a.mp4']);
  });

  test('recent files come from other projects, each path once', () async {
    await bank.add([
      _item('1', 'p1', '/a.mp4', 1),
      _item('2', 'p2', '/b.mp4', 2),
      _item('3', 'p2', '/c.mp4', 3),
    ]);

    final recent = await bank.recent(exceptProjectId: 'p1');
    expect(recent.map((i) => i.path), ['/c.mp4', '/b.mp4']);
  });

  test('files gone from the device are forgotten', () async {
    await bank.add([_item('1', 'p1', '/a.mp4', 1)]);
    files.remove('/a.mp4');

    expect(await bank.itemsOf('p1'), isEmpty);
    files.add('/a.mp4');
    expect(await bank.itemsOf('p1'), isEmpty);
  });

  test('removing takes the item out of the bank only', () async {
    await bank.add([_item('1', 'p1', '/a.mp4', 1)]);
    await bank.remove('1');

    expect(await bank.itemsOf('p1'), isEmpty);
  });
}
