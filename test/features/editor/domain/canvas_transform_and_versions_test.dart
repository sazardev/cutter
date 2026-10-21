import 'package:cutter/features/editor/domain/canvas.dart';
import 'package:cutter/features/editor/domain/canvas_transform_use_cases.dart';
import 'package:cutter/features/editor/domain/clip_transform.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/domain/project_version.dart';
import 'package:cutter/features/editor/domain/rename_project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_editor_ports.dart';

T _ok<T>(EditorResult<T> result) {
  expect(result, isA<Ok<T>>());
  return (result as Ok<T>).value;
}

EditorFailure _failure<T>(EditorResult<T> result) {
  expect(result, isA<Err<T>>());
  return (result as Err<T>).failure;
}

void main() {
  late InMemoryProjectRepository projects;

  setUp(() => projects = InMemoryProjectRepository([buildFixtureProject()]));

  group('Canvas', () {
    test('a new project is vertical 1080x1920 at 30 fps', () {
      expect(Project(id: 'p', name: 'n').canvas, defaultCanvas);
      expect(defaultCanvas.preset, CanvasPreset.portrait);
    });

    test('a custom size has no preset', () {
      expect(const Canvas(width: 1000, height: 1000).preset, isNull);
    });
  });

  group('SetCanvas', () {
    test('changes the canvas and keeps the clips', () async {
      final project = _ok(
        await SetCanvas(projects)(
          projectId: 'p1',
          canvas: CanvasPreset.landscape.canvas(fps: 60),
        ),
      );

      expect(project.canvas, const Canvas(width: 1920, height: 1080, fps: 60));
      expect(project.layers, buildFixtureProject().layers);
      expect(projects.projects['p1']!.canvas.width, 1920);
    });

    test('rejects a size the engine cannot render', () async {
      final failure = _failure(
        await SetCanvas(projects)(
          projectId: 'p1',
          canvas: const Canvas(width: 8000, height: 1080),
        ),
      );

      expect(failure, isA<InvalidCanvas>());
      expect(projects.saveCount, 0);
    });
  });

  group('SetClipTransform', () {
    test('moves and scales a picture', () async {
      const transform = ClipTransform(x: 0.25, y: -0.1, scale: 1.5);
      final project = _ok(
        await SetClipTransform(projects)(
          projectId: 'p1',
          clipId: 'c1',
          transform: transform,
        ),
      );

      expect(project.clipById('c1')!.transform, transform);
      expect(project.clipById('c2')!.transform.isIdentity, isTrue);
    });

    test('a split keeps the transform on both halves', () {
      final clip = buildFixtureProject()
          .clipById('c1')!
          .copyWith(transform: const ClipTransform(rotation: 90));
      expect(clip.copyWith(id: 'other').transform.rotation, 90);
    });

    test('rejects a sound clip and an out-of-range transform', () async {
      expect(
        _failure(
          await SetClipTransform(projects)(
            projectId: 'p1',
            clipId: 'm1',
            transform: const ClipTransform(x: 0.1),
          ),
        ),
        isA<IncompatibleClip>(),
      );
      expect(
        _failure(
          await SetClipTransform(projects)(
            projectId: 'p1',
            clipId: 'c1',
            transform: const ClipTransform(opacity: 2),
          ),
        ),
        isA<InvalidTransform>(),
      );
      expect(const ClipTransform(scale: 0.01).isValid, isFalse);
    });
  });

  group('versions', () {
    late InMemoryVersionRepository versions;

    setUp(() => versions = InMemoryVersionRepository());

    test('saving keeps a snapshot under a name', () async {
      final version = _ok(
        await SaveVersion(
          projects,
          versions,
          SequentialIdGenerator(),
          now: () => 42,
        )(projectId: 'p1', name: '  First cut '),
      );

      expect(version.name, 'First cut');
      expect(version.createdAtMs, 42);
      expect(version.durationMs, buildFixtureProject().durationMs);
      expect(versions.snapshots[version.id], buildFixtureProject());
    });

    test('a blank name is rejected', () async {
      final failure = _failure(
        await SaveVersion(projects, versions, SequentialIdGenerator())(
          projectId: 'p1',
          name: '  ',
        ),
      );

      expect(failure, isA<EmptyName>());
      expect(versions.versions, isEmpty);
    });

    test('restoring brings back the saved state', () async {
      final saved = _ok(
        await SaveVersion(projects, versions, SequentialIdGenerator())(
          projectId: 'p1',
          name: 'v1',
        ),
      );
      await projects.save(projects.projects['p1']!.withLayers([]));

      final restored = _ok(
        await RestoreVersion(projects, versions)(
          projectId: 'p1',
          versionId: saved.id,
        ),
      );

      expect(restored, buildFixtureProject());
      expect(projects.projects['p1'], buildFixtureProject());
    });

    test('restoring an unknown version fails', () async {
      final failure = _failure(
        await RestoreVersion(projects, versions)(
          projectId: 'p1',
          versionId: 'nope',
        ),
      );

      expect(failure, const VersionNotFound('nope'));
    });
  });

  group('RenameProject', () {
    test('keeps the new name, trimmed, and saves it at once', () async {
      final renamed = _ok(
        await RenameProject(projects)(projectId: 'p1', name: '  Summer trip '),
      );

      expect(renamed.name, 'Summer trip');
      expect(projects.projects['p1']!.name, 'Summer trip');
    });

    test('cuts a name that is too long', () async {
      final renamed = _ok(
        await RenameProject(projects)(
          projectId: 'p1',
          name: 'x' * (maxProjectNameLength + 20),
        ),
      );

      expect(renamed.name.length, maxProjectNameLength);
    });

    test('a blank name or an unknown project changes nothing', () async {
      expect(
        _failure(await RenameProject(projects)(projectId: 'p1', name: ' ')),
        isA<EmptyName>(),
      );
      expect(
        _failure(await RenameProject(projects)(projectId: 'nope', name: 'a')),
        isA<ProjectNotFound>(),
      );
      expect(projects.projects['p1'], buildFixtureProject());
    });
  });
}
