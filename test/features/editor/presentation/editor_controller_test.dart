import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/presentation/editor_controller.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    )..listen(editorControllerProvider, (_, __) {});
    await controller().load(_projectId);
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  test('load shows the stored project with the playhead at zero', () {
    expect(uiState().project.id, _projectId);
    expect(uiState().playheadMs, 0);
    expect(uiState().selectedClipId, isNull);
    expect(layerClips(_videoLayerId), hasLength(2));
  });

  test('load of an unknown project ends in an error state', () async {
    await controller().load('missing');

    expect(container.read(editorControllerProvider).hasError, isTrue);
  });

  test('seek clamps the playhead to zero', () {
    controller().seek(-500);
    expect(uiState().playheadMs, 0);

    controller().seek(1234);
    expect(uiState().playheadMs, 1234);
  });

  test('splits the selected clip into two adjacent clips', () async {
    controller()
      ..selectClip('c1')
      ..seek(1000);
    expect(controller().canSplit, isTrue);

    await controller().splitAtPlayhead();

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
    expect(controller().canSplit, isFalse);

    await controller().splitAtPlayhead();

    expect(uiState().failure, isNotNull);
    expect(layerClips(_videoLayerId), hasLength(2));
  });

  test('split with the playhead outside the clip is rejected', () async {
    controller()
      ..selectClip('c1')
      ..seek(_clipDurationMs + 500);
    expect(controller().canSplit, isFalse);

    await controller().splitAtPlayhead();

    expect(uiState().failure, isNotNull);
    expect(layerClips(_videoLayerId), hasLength(2));
  });

  test('canSplit is false without a selected clip', () {
    controller().seek(1000);

    expect(controller().canSplit, isFalse);
  });

  test('moves the selected clip later when the range is free', () async {
    controller().selectClip('c2');

    await controller().nudgeSelected(500);

    expect(uiState().failure, isNull);
    expect(clipById('c2').startMs, _clipDurationMs + 2000 + 500);
  });

  test('move onto an occupied range fails and keeps both clips', () async {
    controller().selectClip('c2');

    await controller().nudgeSelected(-3000);

    expect(uiState().failure, isNotNull);
    expect(clipById('c2').startMs, _clipDurationMs + 2000);
    expect(clipById('c1').startMs, 0);
  });

  test('selecting a clip clears the previous failure', () async {
    controller().selectClip('c1');
    await controller().splitAtPlayhead();
    expect(uiState().failure, isNotNull);

    controller().selectClip('c2');

    expect(uiState().failure, isNull);
  });

  test('clearFailure removes the recorded failure', () async {
    controller().selectClip('c1');
    await controller().splitAtPlayhead();
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
    controller().selectClip('c1');

    await controller().trimSelectedClip(inPointMs: 0, outPointMs: 2000);

    expect(uiState().failure, isNull);
    final clip = clipById('c1');
    expect(clip.inPointMs, 0);
    expect(clip.outPointMs, 2000);
    expect(clip.durationMs, 2000);
  });

  test('a trim that leaves no duration is rejected and keeps the clip',
      () async {
    controller().selectClip('c1');

    await controller().trimSelectedClip(inPointMs: 0, outPointMs: 50);

    expect(uiState().failure, isNotNull);
    expect(clipById('c1').outPointMs, _clipDurationMs);
  });

  test('setting one adjustment keeps the other ones', () async {
    controller().selectClip('c1');

    await controller().setAdjustment('brightness', 0.5);
    expect(uiState().failure, isNull);

    await controller().setAdjustment('contrast', -0.25);

    final clip = clipById('c1');
    expect(clip.adjustments, {'brightness': 0.5, 'contrast': -0.25});
  });

  test('an unknown adjustment key is rejected and changes nothing', () async {
    controller().selectClip('c1');

    await controller().setAdjustment('sepia', 0.5);

    expect(uiState().failure, isNotNull);
    expect(clipById('c1').adjustments, isEmpty);
  });

  test('an edit is persisted and survives a reload', () async {
    controller().selectClip('c1');
    await controller().toggleReverse();

    await controller().load(_projectId);

    expect(clipById('c1').reversed, isTrue);
  });
}
