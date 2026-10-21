import 'dart:io';
import 'dart:typed_data';

import 'package:cutter/features/backup/data/backup_reader.dart';
import 'package:cutter/features/backup/data/backup_writer.dart';
import 'package:cutter/features/backup/domain/backup_format.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

class _Ids implements IdGenerator {
  int _n = 0;

  @override
  String next() => 'new-${_n++}';
}

Clip _clip(String id, String uri, {int start = 0}) => Clip(
      id: id,
      layerId: 'layer',
      assetId: 'asset-$id',
      sourceUri: uri,
      kind: MediaKind.video,
      startMs: start,
      inPointMs: 500,
      outPointMs: 4000,
      sourceDurationMs: 8000,
    );

void main() {
  late Directory sandbox;
  late File a;
  late File b;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('cutter_backup_test');
    a = File('${sandbox.path}/a.mp4')
      ..writeAsBytesSync(Uint8List.fromList(List.generate(3000000, (i) => i)));
    b = File('${sandbox.path}/b.mp4')..writeAsStringSync('second video');
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  Project project() => Project(
        id: 'p1',
        name: 'Holiday',
        layers: [
          Layer(
            id: 'layer',
            name: '',
            kind: MediaKind.video,
            clips: [
              _clip('c1', a.path),
              _clip('c2', b.path, start: 4000),
              _clip('c3', '${sandbox.path}/gone.mp4', start: 8000),
              _clip('c4', a.path, start: 12000),
            ],
          ),
        ],
      );

  test('a backup restores the project and its media as new copies', () async {
    final out = '${sandbox.path}/holiday.cutter';

    final result = await writeBackup(project(), out);

    expect(result.mediaCount, 2);
    expect(result.missingCount, 1);
    expect(File(out).existsSync(), isTrue);
    expect(File('$out.partial').existsSync(), isFalse);

    final restored = await readBackup(
      out,
      mediaRoot: Directory('${sandbox.path}/restored'),
      ids: _Ids(),
      restoredName: 'Holiday (restored)',
    );

    expect(restored.name, 'Holiday (restored)');
    expect(restored.id, isNot('p1'));
    final clips = restored.layers.single.clips;
    expect(clips.map((c) => c.id).toSet(), hasLength(4));
    expect(clips.any((c) => c.id == 'c1'), isFalse);
    expect(clips[0].layerId, restored.layers.single.id);
    // Both clips of the same file share one unpacked copy.
    expect(clips[0].sourceUri, clips[3].sourceUri);
    expect(clips[0].sourceUri, startsWith('${sandbox.path}/restored/'));
    expect(
      File(clips[0].sourceUri).readAsBytesSync(),
      a.readAsBytesSync(),
    );
    expect(File(clips[1].sourceUri).readAsStringSync(), 'second video');
    // The trims survive; the missing file stays missing.
    expect(clips[0].inPointMs, 500);
    expect(clips[0].outPointMs, 4000);
    expect(clips[2].sourceUri, '${sandbox.path}/gone.mp4');
  });

  test('a file that is not a backup is refused', () async {
    await expectLater(
      readBackup(
        b.path,
        mediaRoot: Directory('${sandbox.path}/restored'),
        ids: _Ids(),
      ),
      throwsA(
        isA<BackupException>()
            .having((e) => e.failure, 'failure', BackupFailure.notABackup),
      ),
    );
  });

  test('a truncated backup is damaged and leaves nothing unpacked', () async {
    final out = '${sandbox.path}/holiday.cutter';
    await writeBackup(project(), out);
    final bytes = File(out).readAsBytesSync();
    File(out).writeAsBytesSync(bytes.sublist(0, bytes.length - 100));
    final root = Directory('${sandbox.path}/restored');

    await expectLater(
      readBackup(out, mediaRoot: root, ids: _Ids()),
      throwsA(
        isA<BackupException>()
            .having((e) => e.failure, 'failure', BackupFailure.damaged),
      ),
    );
    expect(root.existsSync() ? root.listSync() : [], isEmpty);
  });

  test('a backup from a newer Cutter is refused with its own reason', () async {
    final out = '${sandbox.path}/holiday.cutter';
    await writeBackup(project(), out);
    final bytes = File(out).readAsBytesSync();
    ByteData.sublistView(bytes).setUint32(8, backupFormat + 1);
    File(out).writeAsBytesSync(bytes);

    await expectLater(
      readBackup(
        out,
        mediaRoot: Directory('${sandbox.path}/restored'),
        ids: _Ids(),
      ),
      throwsA(
        isA<BackupException>()
            .having((e) => e.failure, 'failure', BackupFailure.newerVersion),
      ),
    );
  });

  test('a missing backup file is an io failure', () async {
    await expectLater(
      readBackup(
        '${sandbox.path}/nothing.cutter',
        mediaRoot: Directory('${sandbox.path}/restored'),
        ids: _Ids(),
      ),
      throwsA(isA<BackupException>()),
    );
  });
}
