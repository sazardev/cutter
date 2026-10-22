import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/core/settings/settings_store.dart';
import 'package:cutter/features/editor/data/settings_animation_preset_repository.dart';
import 'package:cutter/features/editor/domain/animation_preset.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_editor_ports.dart';

Clip _clip(
  String id,
  MediaKind kind, {
  String? animIn,
  int animInMs = 0,
  String? animOut,
  int animOutMs = 0,
}) =>
    Clip(
      id: id,
      layerId: 'l',
      assetId: 'a',
      sourceUri: '/$id',
      kind: kind,
      startMs: 0,
      inPointMs: 0,
      outPointMs: 4000,
      sourceDurationMs: 4000,
      animIn: animIn,
      animInMs: animInMs,
      animOut: animOut,
      animOutMs: animOutMs,
    );

class _Memory implements AnimationPresetRepository {
  final List<AnimationPreset> items = [];

  @override
  Future<List<AnimationPreset>> all() async => List.of(items);

  @override
  Future<void> save(AnimationPreset preset) async {
    items
      ..removeWhere((p) => p.id == preset.id)
      ..add(preset);
  }

  @override
  Future<void> delete(String id) async => items.removeWhere((p) => p.id == id);
}

class _Ids implements IdGenerator {
  int n = 0;

  @override
  String next() => 'id-${n++}';
}

void main() {
  test('every built-in preset is valid and has a distinct id', () {
    expect(
        builtInAnimationPresets.every((p) => p.isValid && !p.isEmpty), isTrue);
    expect(
      builtInAnimationPresets.map((p) => p.id).toSet(),
      hasLength(builtInAnimationPresets.length),
    );
    expect(builtInAnimationPresets.every((p) => p.builtIn), isTrue);
  });

  test('a preset with an unknown animation or a too long one is invalid', () {
    const unknown = AnimationPreset(
      id: 'x',
      animIn: 'teleport',
      animInMs: 500,
      animOut: null,
      animOutMs: 0,
    );
    const tooLong = AnimationPreset(
      id: 'y',
      animIn: 'fade',
      animInMs: maxClipAnimationMs + 1,
      animOut: null,
      animOutMs: 0,
    );
    expect(unknown.isValid, isFalse);
    expect(tooLong.isValid, isFalse);
  });

  group('SaveAnimationPreset', () {
    test('saves the animation of a clip under a trimmed, cut name', () async {
      final presets = _Memory();
      final save = SaveAnimationPreset(presets, _Ids());
      final clip = _clip(
        'c',
        MediaKind.video,
        animIn: 'zoom_in',
        animInMs: 700,
        animOut: 'fade',
        animOutMs: 300,
      );

      final result = await save(clip: clip, name: '  ${'N' * 60}  ');

      final preset = (result as Ok<AnimationPreset>).value;
      expect(preset.name, hasLength(maxPresetNameLength));
      expect(preset.animIn, 'zoom_in');
      expect(preset.animOutMs, 300);
      expect(preset.builtIn, isFalse);
      expect(presets.items, [preset]);
    });

    test('refuses a blank name and a clip that does not animate', () async {
      final presets = _Memory();
      final save = SaveAnimationPreset(presets, _Ids());
      final animated =
          _clip('c', MediaKind.video, animIn: 'fade', animInMs: 500);

      expect(await save(clip: animated, name: '  '), isA<Err>());
      expect(
        await save(clip: _clip('d', MediaKind.video), name: 'Plain'),
        isA<Err>(),
      );
      expect(presets.items, isEmpty);
    });
  });

  group('ApplyAnimationPreset', () {
    final project = Project(
      id: 'p',
      name: 'P',
      layers: [
        Layer(
          id: 'l',
          name: '',
          kind: MediaKind.video,
          clips: [
            _clip('a', MediaKind.video),
            _clip('b', MediaKind.image, animIn: 'spin', animInMs: 900),
            _clip('s', MediaKind.audio),
          ],
        ),
      ],
    );
    const preset = AnimationPreset(
      id: 'pop',
      animIn: 'pop',
      animInMs: 400,
      animOut: null,
      animOutMs: 0,
    );

    test('animates every compatible clip in one save and skips sound',
        () async {
      final repository = InMemoryProjectRepository([project]);

      final result = await ApplyAnimationPreset(repository)(
        projectId: 'p',
        clipIds: ['a', 'b', 's'],
        preset: preset,
      );

      final clips = (result as Ok<Project>).value.layers.single.clips;
      expect(clips.firstWhere((c) => c.id == 'a').animIn, 'pop');
      final b = clips.firstWhere((c) => c.id == 'b');
      expect(b.animIn, 'pop');
      // A preset with no exit clears the exit the clip had.
      expect(b.animOut, isNull);
      expect(clips.firstWhere((c) => c.id == 's').animIn, isNull);
      expect(repository.saveCount, 1);
    });

    test('is refused when nothing can be animated or the preset is bad',
        () async {
      final repository = InMemoryProjectRepository([project]);
      final apply = ApplyAnimationPreset(repository);

      expect(
        await apply(projectId: 'p', clipIds: ['s'], preset: preset),
        isA<Err>(),
      );
      expect(
        await apply(
          projectId: 'p',
          clipIds: ['a'],
          preset: const AnimationPreset(
            id: 'bad',
            animIn: 'teleport',
            animInMs: 1,
            animOut: null,
            animOutMs: 0,
          ),
        ),
        isA<Err>(),
      );
      expect(repository.saveCount, 0);
    });
  });

  group('SettingsAnimationPresetRepository', () {
    late AppDatabase db;
    late SettingsStore store;
    late SettingsAnimationPresetRepository repository;

    setUp(() {
      db = AppDatabase.inMemory();
      store = SettingsStore(db);
      repository = SettingsAnimationPresetRepository(store);
    });

    tearDown(() => db.close());

    test('keeps presets, replaces by id and deletes', () async {
      expect(await repository.all(), isEmpty);
      const a = AnimationPreset(
        id: 'a',
        name: 'One',
        animIn: 'fade',
        animInMs: 500,
        animOut: null,
        animOutMs: 0,
      );
      await repository.save(a);
      await repository.save(
        const AnimationPreset(
          id: 'b',
          name: 'Two',
          animIn: null,
          animInMs: 0,
          animOut: 'spin',
          animOutMs: 300,
        ),
      );
      await repository.save(
        const AnimationPreset(
          id: 'a',
          name: 'One renamed',
          animIn: 'fade',
          animInMs: 800,
          animOut: null,
          animOutMs: 0,
        ),
      );

      final all = await repository.all();
      expect(all.map((p) => p.name), ['Two', 'One renamed']);

      await repository.delete('b');
      expect((await repository.all()).single.id, 'a');
    });

    test('an unreadable value counts as no presets', () async {
      await store.write('animation_presets', 'not json');

      expect(await repository.all(), isEmpty);
    });
  });
}
