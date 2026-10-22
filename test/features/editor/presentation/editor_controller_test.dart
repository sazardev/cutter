import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/core/engine/media_engine.dart';
import 'package:cutter/features/editor/data/engine_media_inspector.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/clip_text.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/presentation/checkpoint_labels.dart';
import 'package:cutter/features/editor/presentation/editor_controller.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/engine/fake_media_engine.dart';

const _projectId = 'p1';
const _videoLayerId = 'l1';
const _audioLayerId = 'l2';
const _clipDurationMs = 4000;

Future<void> _seedProject(AppDatabase database) async {
  await database.into(database.editorProjects).insert(
        const EditorProjectsCompanion(
          id: Value(_projectId),
          name: Value('Test project'),
          createdAtMs: Value(0),
          updatedAtMs: Value(0),
          canvasWidth: Value(1080),
          canvasHeight: Value(1920),
          fps: Value(60),
        ),
      );
  await _insertLayer(database, _videoLayerId, 0, 'video');
  await _insertLayer(database, _audioLayerId, 1, 'audio');
  await _insertClip(database, 'c1', _videoLayerId, 0, 0, 'file:///video.mp4');
  await _insertClip(
    database,
    'c2',
    _videoLayerId,
    1,
    _clipDurationMs + 2000,
    'file:///video2.mp4',
  );
  await _insertClip(database, 'a1', _audioLayerId, 0, 0, 'file:///music.mp3');
}

Future<void> _insertLayer(
  AppDatabase database,
  String id,
  int position,
  String kind,
) {
  return database.into(database.editorLayers).insert(
        EditorLayersCompanion(
          id: Value(id),
          projectId: const Value(_projectId),
          position: Value(position),
          kind: Value(kind),
          volume: const Value(1),
          muted: const Value(false),
        ),
      );
}

Future<void> _insertClip(
  AppDatabase database,
  String id,
  String layerId,
  int sortKey,
  int startMs,
  String sourceUri,
) {
  return database.into(database.editorClips).insert(
        EditorClipsCompanion(
          id: Value(id),
          layerId: Value(layerId),
          sortKey: Value(sortKey),
          sourceUri: Value(sourceUri),
          startMs: Value(startMs),
          durationMs: const Value(_clipDurationMs),
          inPointMs: const Value(0),
          outPointMs: const Value(_clipDurationMs),
          reversed: const Value(false),
          volume: const Value(1),
          filterId: const Value(null),
          adjustmentsJson: const Value('{}'),
        ),
      );
}

void main() {
  late AppDatabase database;
  late ProviderContainer container;

  EditorController controller() =>
      container.read(editorControllerProvider.notifier);

  EditorUiState uiState() =>
      container.read(editorControllerProvider).requireValue;

  List<Clip> layerClips(String layerId) {
    final layer = uiState().project.layers.firstWhere(
          (layer) => layer.id == layerId,
        );
    final clips = [...layer.clips]
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    return clips;
  }

  Clip clipById(String id) {
    for (final layer in uiState().project.layers) {
      for (final clip in layer.clips) {
        if (clip.id == id) return clip;
      }
    }
    throw StateError('Clip $id not found');
  }

  setUp(() async {
    database = AppDatabase.inMemory();
    await _seedProject(database);
    final engine = FakeMediaEngine(
      media: {
        '/media/clip.mp4': fakeVideo,
        '/media/song.m4a': fakeSound,
        '/media/blip.wav': const MediaInfo(
          kind: EngineMediaKind.audio,
          durationMs: 20,
          width: 0,
          height: 0,
          hasAudio: true,
          frameRate: 0,
          rotation: 0,
        ),
      },
    );
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        mediaEngineProvider.overrideWithValue(engine),
        mediaInspectorProvider.overrideWith(
          (ref) => EngineMediaInspector(
            engine,
            ref.watch(idGeneratorProvider),
            keep: (path) async => path,
          ),
        ),
      ],
    )..listen(editorControllerProvider, (_, __) {});
    await controller().load(_projectId);
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  test('load shows the stored project with nothing to undo', () {
    expect(uiState().project.id, _projectId);
    expect(uiState().canUndo, isFalse);
    expect(uiState().selectedClipId, isNull);
    expect(layerClips(_videoLayerId), hasLength(2));
  });

  test('load of an unknown project ends in an error state', () async {
    await controller().load('missing');

    expect(container.read(editorControllerProvider).hasError, isTrue);
  });

  test('splits the selected clip into two adjacent clips', () async {
    controller().selectClip('c1');
    expect(controller().canSplitAt(1000), isTrue);

    await controller().splitAt(1000);

    expect(uiState().failure, isNull);
    final clips = layerClips(_videoLayerId);
    expect(clips, hasLength(3));
    final first = clips[0];
    final second = clips[1];
    expect(first.durationMs, 1000);
    expect(second.startMs, first.startMs + first.durationMs);
    expect(first.durationMs + second.durationMs, _clipDurationMs);
  });

  test('split at the clip start is rejected and changes nothing', () async {
    controller().selectClip('c1');
    expect(controller().canSplitAt(0), isFalse);

    await controller().splitAt(0);

    expect(uiState().failure, isNotNull);
    expect(layerClips(_videoLayerId), hasLength(2));
  });

  test('split with the playhead outside the clip is rejected', () async {
    controller().selectClip('c1');
    expect(controller().canSplitAt(_clipDurationMs + 500), isFalse);

    await controller().splitAt(_clipDurationMs + 500);

    expect(uiState().failure, isNotNull);
    expect(layerClips(_videoLayerId), hasLength(2));
  });

  test('canSplitAt is false without a selected clip', () {
    expect(controller().canSplitAt(1000), isFalse);
  });

  test('moves the selected clip later when the range is free', () async {
    await controller().moveClip('c2', _videoLayerId, _clipDurationMs + 2500);

    expect(uiState().failure, isNull);
    expect(clipById('c2').startMs, _clipDurationMs + 2000 + 500);
  });

  test('move onto an occupied range fails and keeps both clips', () async {
    await controller().moveClip('c2', _videoLayerId, _clipDurationMs - 1000);

    expect(uiState().failure, isNotNull);
    expect(clipById('c2').startMs, _clipDurationMs + 2000);
    expect(clipById('c1').startMs, 0);
  });

  test('selecting a clip clears the previous failure', () async {
    controller().selectClip('c1');
    await controller().splitAt(0);
    expect(uiState().failure, isNotNull);

    controller().selectClip('c2');

    expect(uiState().failure, isNull);
  });

  test('clearFailure removes the recorded failure', () async {
    controller().selectClip('c1');
    await controller().splitAt(0);
    expect(uiState().failure, isNotNull);

    controller().clearFailure();

    expect(uiState().failure, isNull);
  });

  test('reverses a video clip and turns it back', () async {
    controller().selectClip('c1');

    await controller().toggleReverse();
    expect(uiState().failure, isNull);
    expect(clipById('c1').reversed, isTrue);

    await controller().toggleReverse();
    expect(clipById('c1').reversed, isFalse);
  });

  test('reversing an audio clip is rejected', () async {
    controller().selectClip('a1');

    await controller().toggleReverse();

    expect(uiState().failure, isNotNull);
    expect(clipById('a1').reversed, isFalse);
  });

  test('sets the clip volume and mutes at zero', () async {
    controller().selectClip('a1');

    await controller().setClipVolume(0.5);
    expect(uiState().failure, isNull);
    expect(clipById('a1').volume, 0.5);

    await controller().setClipVolume(0);
    expect(clipById('a1').volume, 0);
  });

  test('trims the selected clip to the given source range', () async {
    await controller().trimClip('c1', inPointMs: 0, outPointMs: 2000);

    expect(uiState().failure, isNull);
    final clip = clipById('c1');
    expect(clip.inPointMs, 0);
    expect(clip.outPointMs, 2000);
    expect(clip.durationMs, 2000);
  });

  test('a trim that leaves no duration is rejected and keeps the clip',
      () async {
    await controller().trimClip('c1', inPointMs: 0, outPointMs: 20);

    expect(uiState().failure, isNotNull);
    expect(clipById('c1').outPointMs, _clipDurationMs);
  });

  test('saves the adjustments of the selected clip', () async {
    controller().selectClip('c1');

    await controller().setAdjustments({'brightness': 0.5, 'contrast': -0.25});

    expect(uiState().failure, isNull);
    final clip = clipById('c1');
    expect(clip.adjustments, {'brightness': 0.5, 'contrast': -0.25});
  });

  test('an unknown adjustment key is rejected and changes nothing', () async {
    controller().selectClip('c1');

    await controller().setAdjustments({'sepia': 0.5});

    expect(uiState().failure, isNotNull);
    expect(clipById('c1').adjustments, isEmpty);
  });

  test('an edit is persisted and survives a reload', () async {
    controller().selectClip('c1');
    await controller().toggleReverse();

    await controller().load(_projectId);

    expect(clipById('c1').reversed, isTrue);
  });

  test('undo and redo walk through the edits and are saved', () async {
    controller().selectClip('c1');
    await controller().toggleReverse();
    await controller().setClipVolume(0.25);
    expect(uiState().canUndo, isTrue);

    await controller().undo();
    expect(clipById('c1').volume, 1);
    expect(clipById('c1').reversed, isTrue);
    expect(uiState().canRedo, isTrue);

    await controller().undo();
    expect(clipById('c1').reversed, isFalse);
    expect(uiState().canUndo, isFalse);

    await controller().redo();
    expect(clipById('c1').reversed, isTrue);

    await controller().load(_projectId);
    expect(clipById('c1').reversed, isTrue);
  });

  test('a rejected edit records nothing to undo', () async {
    controller().selectClip('c1');
    await controller().splitAt(0);

    expect(uiState().canUndo, isFalse);
  });

  test('deleting on the main layer closes the gap', () async {
    controller().selectClip('c1');

    await controller().deleteSelected();

    expect(uiState().selectedClipId, isNull);
    final clips = layerClips(_videoLayerId);
    expect(clips.map((c) => (c.id, c.startMs)), [('c2', 2000)]);
  });

  test('duplicating selects the copy placed right after the original',
      () async {
    controller().selectClip('c1');

    await controller().duplicateSelected();

    final copyId = uiState().selectedClipId!;
    expect(copyId, isNot('c1'));
    expect(clipById(copyId).startMs, _clipDurationMs);
    expect(clipById('c2').startMs, _clipDurationMs * 2 + 2000);
  });

  test('mutes a layer', () async {
    await controller().setLayerMuted(_audioLayerId, muted: true);

    final layer =
        uiState().project.layers.firstWhere((l) => l.id == _audioLayerId);
    expect(layer.muted, isTrue);
  });

  test('imports playable files and reports the others', () async {
    final outcome = await controller().importFiles(
      ['/media/clip.mp4', '/media/notes.txt', '/media/song.m4a'],
      atMs: 1000,
    );

    expect(outcome.imported, 2);
    expect(outcome.rejected, ['/media/notes.txt']);
    final video = layerClips(_videoLayerId);
    expect(video.last.sourceUri, '/media/clip.mp4');
    expect(video.last.startMs, _clipDurationMs * 2 + 2000);
    final sounds = [
      for (final layer in uiState().project.layers)
        if (layer.kind == MediaKind.audio)
          for (final clip in layer.clips)
            if (clip.sourceUri == '/media/song.m4a') clip,
    ];
    expect(sounds.single.startMs, 1000);
    expect(uiState().selectedClipId, sounds.single.id);
    expect(uiState().importing, isFalse);
  });

  test('an import of only unreadable files changes nothing', () async {
    final outcome =
        await controller().importFiles(['/media/notes.txt'], atMs: 0);

    expect(outcome.imported, 0);
    expect(uiState().canUndo, isFalse);
  });

  test('a file too short to be a clip is reported, the rest imports', () async {
    final outcome = await controller().importFiles(
      ['/media/clip.mp4', '/media/blip.wav'],
      atMs: 0,
    );

    expect(outcome.imported, 1);
    expect(outcome.rejected, ['/media/blip.wav']);
  });

  group('restore points', () {
    final labels = CheckpointLabels(
      start: 'Start',
      auto: (at) => 'Auto',
      beforeRestore: (name) => 'Before $name',
    );

    Future<List<String>> names() async => [
          for (final v
              in await container.read(versionRepositoryProvider).versionsOf(
                    _projectId,
                  ))
            v.name,
        ];

    test('opening a project saves a first point, only once', () async {
      await controller().load(_projectId, labels: labels);
      await controller().load(_projectId, labels: labels);

      expect(await names(), ['Start']);
    });

    test('without labels nothing is saved by itself', () async {
      expect(await names(), isEmpty);
    });

    test('restoring first saves the state it replaces', () async {
      await controller().load(_projectId, labels: labels);
      final start = (await container
              .read(versionRepositoryProvider)
              .versionsOf(_projectId))
          .single;
      controller().selectClip('c1');
      await controller().splitAt(1000);

      await controller().restoreVersion(start.id);

      expect(await names(), containsAll(['Start', 'Before Start']));
      expect(layerClips(_videoLayerId), hasLength(2));
      // The point saved before is the split state, so it can come back.
      final before = (await container
              .read(versionRepositoryProvider)
              .versionsOf(_projectId))
          .firstWhere((v) => v.name == 'Before Start');
      await controller().restoreVersion(before.id);
      expect(layerClips(_videoLayerId), hasLength(3));
    });
  });

  test('renaming keeps the name, can be undone and ignores blanks', () async {
    expect(await controller().rename('  Summer trip '), isTrue);
    expect(uiState().project.name, 'Summer trip');
    final stored = await container.read(projectRepositoryProvider).find(
          _projectId,
        );
    expect(stored!.name, 'Summer trip');

    expect(await controller().rename('   '), isFalse);
    expect(uiState().project.name, 'Summer trip');

    await controller().undo();
    expect(uiState().project.name, 'Test project');
  });

  test('a layer left without clips is removed and stays removed', () async {
    controller().selectClip('a1');
    await controller().deleteSelected();

    final layerIds = [for (final l in uiState().project.layers) l.id];
    expect(layerIds, [_videoLayerId]);
    final stored = await container.read(projectRepositoryProvider).find(
          _projectId,
        );
    expect(stored!.layers.map((l) => l.id), [_videoLayerId]);

    await controller().undo();
    expect(uiState().project.layers, hasLength(2));
  });

  test('layers can be moved among the others and the order is kept', () async {
    expect(await controller().moveLayer(_audioLayerId, -1), isTrue);
    expect(
      [for (final l in uiState().project.layers) l.id],
      [_audioLayerId, _videoLayerId],
    );
    final stored = await container.read(projectRepositoryProvider).find(
          _projectId,
        );
    expect(stored!.layers.first.id, _audioLayerId);

    // Past either end there is nowhere to go.
    expect(await controller().moveLayer(_audioLayerId, -1), isFalse);
    await controller().undo();
    expect(uiState().project.layers.first.id, _videoLayerId);
  });

  group('text', () {
    const hello = ClipText(content: 'Hola');

    test('adds a text over the video, selects it and measures it', () async {
      final id = await controller().addText(hello, 1000);

      expect(id, isNotNull);
      expect(uiState().selectedClipId, id);
      final layer = uiState().project.layers.first;
      expect(layer.kind, MediaKind.text);
      final clip = clipById(id!);
      expect(clip.text, hello);
      expect(clip.startMs, 1000);
      expect(clip.sourceWidth, greaterThan(0));
      expect(clip.sourceHeight, greaterThan(0));
      final stored = await container.read(projectRepositoryProvider).find(
            _projectId,
          );
      expect(stored!.clipById(id)!.text, hello);
    });

    test('typing in a burst is one step of undo, and re-measures', () async {
      final id = (await controller().addText(hello, 0))!;
      final before = clipById(id).sourceWidth;

      await controller().setText(id, hello.copyWith(content: 'Hola m'));
      await controller().setText(id, hello.copyWith(content: 'Hola mundo!'));

      expect(clipById(id).text!.content, 'Hola mundo!');
      expect(clipById(id).sourceWidth, greaterThan(before));

      await controller().undo();
      expect(clipById(id).text, hello);
      await controller().undo();
      expect(
        uiState().project.layers.any((l) => l.kind == MediaKind.text),
        isFalse,
      );
    });

    test('deleting the only text removes its layer', () async {
      await controller().addText(hello, 0);
      await controller().deleteSelected();

      expect(
        uiState().project.layers.any((l) => l.kind == MediaKind.text),
        isFalse,
      );
    });
  });
}
