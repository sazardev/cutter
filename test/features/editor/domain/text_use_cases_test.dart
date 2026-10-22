import 'package:cutter/features/editor/domain/clip_text.dart';
import 'package:cutter/features/editor/domain/clip_timing_use_cases.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/domain/text_use_cases.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_editor_ports.dart';

Project _ok(EditorResult<Project> result) {
  expect(result, isA<Ok<Project>>());
  return (result as Ok<Project>).value;
}

const _hello = ClipText(content: 'Hola');

void main() {
  late InMemoryProjectRepository repository;
  late AddTextClip addText;
  late String projectId;
  late SequentialIdGenerator ids;

  setUp(() {
    final project = buildFixtureProject();
    projectId = project.id;
    repository = InMemoryProjectRepository([project]);
    ids = SequentialIdGenerator();
    addText = AddTextClip(repository, ids);
  });

  Future<EditorResult<Project>> add({int at = 0, ClipText text = _hello}) =>
      addText(
        projectId: projectId,
        text: text,
        width: 300,
        height: 100,
        startMs: at,
      );

  group('AddTextClip', () {
    test('puts the text on a new text layer in front of the others', () async {
      final project = _ok(await add(at: 1000));
      final layer = project.layers.first;
      expect(layer.kind, MediaKind.text);
      final clip = layer.clips.single;
      expect(clip.text, _hello);
      expect(clip.startMs, 1000);
      expect(clip.durationMs, defaultTextDurationMs);
      expect((clip.sourceWidth, clip.sourceHeight), (300, 100));
      expect(clip.transform.y, 0);
    });

    test('texts one after the other share a layer', () async {
      _ok(await add());
      final project = _ok(await add(at: defaultTextDurationMs));
      final texts = project.layers.where((l) => l.kind == MediaKind.text);
      expect(texts, hasLength(1));
      expect(texts.single.clips, hasLength(2));
    });

    test('texts that share time go on layers of their own, nudged down',
        () async {
      _ok(await add());
      final project = _ok(await add(at: 500));
      final texts =
          project.layers.where((l) => l.kind == MediaKind.text).toList();
      expect(texts, hasLength(2));
      expect(texts.first.clips.single.transform.y, greaterThan(0));
    });

    test('rejects an invalid look and saves nothing', () async {
      final saves = repository.saveCount;
      final result = await add(text: const ClipText(size: 5));
      expect(result, isA<Err<Project>>());
      expect((result as Err<Project>).failure, isA<InvalidText>());
      expect(repository.saveCount, saves);
    });
  });

  group('SetClipText', () {
    test('changes the words and the frame of the clip', () async {
      final added = _ok(await add());
      final id = added.layers.first.clips.single.id;
      final project = _ok(
        await SetClipText(repository)(
          projectId: projectId,
          clipId: id,
          text: _hello.copyWith(content: 'Adiós', color: 0xFFFF0000),
          width: 420,
          height: 120,
        ),
      );
      final clip = project.clipById(id)!;
      expect(clip.text!.content, 'Adiós');
      expect(clip.text!.color, 0xFFFF0000);
      expect((clip.sourceWidth, clip.sourceHeight), (420, 120));
    });

    test('refuses a clip that is not a text', () async {
      final result = await SetClipText(repository)(
        projectId: projectId,
        clipId: 'c1',
        text: _hello,
        width: 1,
        height: 1,
      );
      expect((result as Err<Project>).failure, isA<InvalidText>());
    });
  });

  group('a text clip with the existing timeline edits', () {
    test('can be stretched to either side and split in two', () async {
      final added = _ok(await add(at: 2000));
      final clip = added.layers.first.clips.single;
      final stretched = _ok(
        await TrimClip(repository)(
          projectId: projectId,
          clipId: clip.id,
          inPointMs: clip.inPointMs - 500,
          outPointMs: clip.outPointMs + 1000,
        ),
      );
      final longer = stretched.clipById(clip.id)!;
      expect(longer.startMs, 1500);
      expect(longer.durationMs, defaultTextDurationMs + 1500);

      final split = _ok(
        await SplitClip(repository, ids)(
          projectId: projectId,
          clipId: clip.id,
          atMs: 3000,
        ),
      );
      final halves = split.layers.first.clips;
      expect(halves, hasLength(2));
      expect(halves.every((c) => c.text == _hello), isTrue);
    });
  });
}
