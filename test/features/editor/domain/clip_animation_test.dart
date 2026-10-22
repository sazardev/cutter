import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/features/editor/data/drift_project_repository.dart';
import 'package:cutter/features/editor/data/editor_dao.dart';
import 'package:cutter/features/editor/data/project_snapshot_codec.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/clip_settings_use_cases.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_editor_ports.dart';

Project _valueOf(EditorResult<Project> result) => (result as Ok<Project>).value;

Matcher _failsWith(EditorFailure failure) => isA<Err<Project>>().having(
      (err) => err.failure,
      'failure',
      failure,
    );

void main() {
  late InMemoryProjectRepository repository;

  setUp(() {
    repository = InMemoryProjectRepository([buildFixtureProject()]);
  });

  group('SetClipAnimation', () {
    test('sets an entrance and an exit on one clip only', () async {
      final result = await SetClipAnimation(repository)(
        projectId: 'p1',
        clipId: 'c1',
        animIn: 'slide_left',
        animInMs: 500,
        animOut: 'fade',
        animOutMs: 800,
      );

      final project = _valueOf(result);
      final clip = project.clipById('c1')!;
      expect((clip.animIn, clip.animInMs), ('slide_left', 500));
      expect((clip.animOut, clip.animOutMs), ('fade', 800));
      expect(project.clipById('c2')!.animIn, isNull);
    });

    test('a null id removes that side and its length', () async {
      final set = SetClipAnimation(repository);
      await set(projectId: 'p1', clipId: 'c1', animIn: 'pop', animInMs: 400);
      final result = await set(projectId: 'p1', clipId: 'c1');

      final clip = _valueOf(result).clipById('c1')!;
      expect((clip.animIn, clip.animInMs, clip.animOut), (null, 0, null));
    });

    test('every listed animation is accepted', () async {
      for (final id in clipAnimationIds) {
        final result = await SetClipAnimation(repository)(
          projectId: 'p1',
          clipId: 'c1',
          animIn: id,
          animInMs: 300,
        );
        expect(result, isA<Ok<Project>>(), reason: id);
      }
    });

    test('rejects an unknown id or a length out of range', () async {
      final set = SetClipAnimation(repository);
      expect(
        await set(projectId: 'p1', clipId: 'c1', animIn: 'nope', animInMs: 1),
        _failsWith(const InvalidAnimation()),
      );
      expect(
        await set(
            projectId: 'p1', clipId: 'c1', animOut: 'fade', animOutMs: -1),
        _failsWith(const InvalidAnimation()),
      );
      expect(
        await set(
          projectId: 'p1',
          clipId: 'c1',
          animIn: 'fade',
          animInMs: maxClipAnimationMs + 1,
        ),
        _failsWith(const InvalidAnimation()),
      );
      expect(
        repository.projects['p1']!.clipById('c1')!.animIn,
        isNull,
        reason: 'nothing saved',
      );
    });

    test('rejects an audio clip', () async {
      final audio = buildFixtureProject()
          .layers
          .expand((l) => l.clips)
          .firstWhere((c) => c.kind == MediaKind.audio);
      final result = await SetClipAnimation(repository)(
        projectId: 'p1',
        clipId: audio.id,
        animIn: 'fade',
        animInMs: 300,
      );
      expect(result, _failsWith(const IncompatibleClip()));
    });
  });

  group('animation storage', () {
    late AppDatabase database;

    setUp(() => database = AppDatabase.inMemory());
    tearDown(() => database.close());

    Project animated() {
      const clip = Clip(
        id: 'a1',
        layerId: 'l1',
        assetId: 'file:///a.png',
        sourceUri: 'file:///a.png',
        kind: MediaKind.image,
        startMs: 0,
        inPointMs: 0,
        outPointMs: 3000,
        sourceDurationMs: 3000,
        animIn: 'zoom_in',
        animInMs: 600,
        animOut: 'spin',
        animOutMs: 900,
      );
      return Project(
        id: 'p',
        name: 'Animated',
        layers: [
          Layer(
            id: 'l1',
            name: '',
            kind: MediaKind.image,
            clips: const [clip],
          ),
        ],
      );
    }

    test('a saved project keeps its animations', () async {
      final repo = DriftProjectRepository(EditorDao(database));
      await repo.save(animated());

      expect(await repo.find('p'), animated());
    });

    test('a saved version keeps its animations', () {
      final decoded = decodeProjectSnapshot(encodeProjectSnapshot(animated()));

      expect(decoded, animated());
    });
  });
}
