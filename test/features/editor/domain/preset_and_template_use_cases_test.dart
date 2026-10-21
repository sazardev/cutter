import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/instantiate_template.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/preset.dart';
import 'package:cutter/features/editor/domain/preset_use_cases.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/domain/template.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_editor_ports.dart';

Project _projectWithConfiguredClip() {
  final base = buildFixtureProject();
  final layer = base.layerById('v1')!;
  final configured = layer.clips.first.copyWith(
    filterId: 'sepia',
    adjustments: const {'brightness': 0.5, 'contrast': -0.25},
    volume: 0.5,
  );
  return base.replaceLayer(
    layer.withClips([configured, layer.clips.last]),
  );
}

EditorFailure _failure<T>(EditorResult<T> result) {
  expect(result, isA<Err<T>>());
  return (result as Err<T>).failure;
}

T _value<T>(EditorResult<T> result) {
  expect(result, isA<Ok<T>>());
  return (result as Ok<T>).value;
}

void main() {
  group('SavePreset', () {
    late InMemoryProjectRepository projects;
    late InMemoryPresetRepository presets;
    late SavePreset savePreset;

    setUp(() {
      projects = InMemoryProjectRepository([_projectWithConfiguredClip()]);
      presets = InMemoryPresetRepository();
      savePreset = SavePreset(projects, presets, SequentialIdGenerator());
    });

    test('saves_and_lists_a_preset_with_the_clip_settings', () async {
      final result = await savePreset(
        projectId: 'p1',
        clipId: 'c1',
        name: '  Warm look  ',
      );

      final preset = _value(result);
      expect(preset.name, 'Warm look');
      expect(preset.filterId, 'sepia');
      expect(preset.adjustments, {'brightness': 0.5, 'contrast': -0.25});
      expect(preset.volume, 0.5);
      final listed = await presets.all();
      expect(listed, hasLength(1));
      expect(listed.single.id, preset.id);
    });

    test('rejects_a_blank_name_and_saves_nothing', () async {
      final result = await savePreset(
        projectId: 'p1',
        clipId: 'c1',
        name: '   ',
      );

      expect(_failure(result), const EmptyName());
      expect(await presets.all(), isEmpty);
    });

    test('rejects_an_unknown_clip', () async {
      final result = await savePreset(
        projectId: 'p1',
        clipId: 'nope',
        name: 'Look',
      );

      expect(_failure(result), const ClipNotFound('nope'));
      expect(await presets.all(), isEmpty);
    });

    test('rejects_an_unknown_project', () async {
      final result = await savePreset(
        projectId: 'missing',
        clipId: 'c1',
        name: 'Look',
      );

      expect(_failure(result), const ProjectNotFound('missing'));
    });
  });

  group('ApplyPreset', () {
    late InMemoryProjectRepository projects;
    late InMemoryPresetRepository presets;
    late ApplyPreset applyPreset;

    setUp(() {
      projects = InMemoryProjectRepository([buildFixtureProject()]);
      presets = InMemoryPresetRepository([
        const Preset(
          id: 'look',
          name: 'Look',
          filterId: 'mono',
          adjustments: {'saturation': -1.0},
          volume: 0.3,
        ),
        const Preset(
          id: 'plain',
          name: 'Plain',
          adjustments: {'brightness': 0.2},
          volume: 0.9,
        ),
      ]);
      applyPreset = ApplyPreset(projects, presets);
    });

    test('applies_every_captured_setting_and_saves', () async {
      final result = await applyPreset(
        projectId: 'p1',
        clipId: 'c2',
        presetId: 'look',
      );

      final clip = _value(result).clipById('c2')!;
      expect(clip.filterId, 'mono');
      expect(clip.adjustments, {'saturation': -1.0});
      expect(clip.volume, 0.3);
      expect(clip.inPointMs, 0);
      expect(clip.outPointMs, 2000);
      expect(projects.projects['p1']!.clipById('c2')!.filterId, 'mono');
      expect(projects.saveCount, 1);
    });

    test('removes_the_filter_when_the_preset_has_none', () async {
      final configured = InMemoryProjectRepository([
        _projectWithConfiguredClip(),
      ]);

      final result = await ApplyPreset(configured, presets)(
        projectId: 'p1',
        clipId: 'c1',
        presetId: 'plain',
      );

      final clip = _value(result).clipById('c1')!;
      expect(clip.filterId, isNull);
      expect(clip.adjustments, {'brightness': 0.2});
      expect(clip.volume, 0.9);
    });

    test('applies_a_preset_without_filter_to_an_audio_clip', () async {
      final result = await applyPreset(
        projectId: 'p1',
        clipId: 'm1',
        presetId: 'plain',
      );

      final clip = _value(result).clipById('m1')!;
      expect(clip.volume, 0.9);
      expect(clip.filterId, isNull);
    });

    test('rejects_a_filter_preset_on_an_audio_clip_and_saves_nothing',
        () async {
      final result = await applyPreset(
        projectId: 'p1',
        clipId: 'm1',
        presetId: 'look',
      );

      expect(_failure(result), const IncompatibleClip());
      expect(projects.saveCount, 0);
      expect(projects.projects['p1']!.clipById('m1')!.volume, 0.8);
    });

    test('rejects_an_unknown_preset', () async {
      final result = await applyPreset(
        projectId: 'p1',
        clipId: 'c1',
        presetId: 'ghost',
      );

      expect(_failure(result), const PresetNotFound('ghost'));
      expect(projects.saveCount, 0);
    });

    test('rejects_an_unknown_clip', () async {
      final result = await applyPreset(
        projectId: 'p1',
        clipId: 'nope',
        presetId: 'look',
      );

      expect(_failure(result), const ClipNotFound('nope'));
      expect(projects.saveCount, 0);
    });
  });

  group('InstantiateTemplate', () {
    const template = Template(
      id: 't1',
      name: 'Intro',
      layers: [
        TemplateLayer(name: 'Main', kind: MediaKind.video),
        TemplateLayer(name: 'Music', kind: MediaKind.audio),
      ],
      slots: [
        MediaSlot(
          id: 's1',
          layerIndex: 0,
          kind: MediaKind.video,
          startMs: 0,
          durationMs: 3000,
        ),
        MediaSlot(
          id: 's2',
          layerIndex: 1,
          kind: MediaKind.audio,
          startMs: 0,
          durationMs: 5000,
        ),
      ],
    );
    const video = MediaAsset(
      id: 'av',
      uri: 'file:///v.mp4',
      kind: MediaKind.video,
      durationMs: 10000,
    );
    const audio = MediaAsset(
      id: 'aa',
      uri: 'file:///a.mp3',
      kind: MediaKind.audio,
      durationMs: 4000,
    );

    late InMemoryProjectRepository projects;
    late InstantiateTemplate instantiate;

    setUp(() {
      projects = InMemoryProjectRepository();
      instantiate = InstantiateTemplate(
        projects,
        InMemoryTemplateCatalog([template]),
        SequentialIdGenerator(),
      );
    });

    test('creates_the_project_with_clips_trimmed_to_the_slots', () async {
      final result = await instantiate(
        templateId: 't1',
        name: 'My intro',
        media: {'s1': video, 's2': audio},
      );

      final project = _value(result);
      expect(project.name, 'My intro');
      expect(project.templateId, 't1');
      expect(project.layers.map((layer) => layer.name), ['Main', 'Music']);
      final videoClip = project.layers[0].clips.single;
      expect(videoClip.outPointMs, 3000);
      expect(videoClip.sourceDurationMs, 10000);
      expect(videoClip.layerId, project.layers[0].id);
      final audioClip = project.layers[1].clips.single;
      expect(audioClip.outPointMs, 4000);
      expect(projects.projects[project.id], project);
      expect(projects.saveCount, 1);
    });

    test('creates_nothing_when_a_slot_has_no_media', () async {
      final result = await instantiate(
        templateId: 't1',
        name: 'My intro',
        media: {'s1': video},
      );

      expect(_failure(result), isA<MissingTemplateMedia>());
      expect(projects.projects, isEmpty);
      expect(projects.saveCount, 0);
    });

    test('creates_nothing_when_the_media_kind_does_not_match', () async {
      final result = await instantiate(
        templateId: 't1',
        name: 'My intro',
        media: {'s1': audio, 's2': audio},
      );

      expect(_failure(result), isA<MissingTemplateMedia>());
      expect(projects.saveCount, 0);
    });

    test('creates_nothing_when_the_media_is_unsupported', () async {
      const broken = MediaAsset(
        id: 'bad',
        uri: 'file:///bad.mp4',
        kind: MediaKind.video,
        durationMs: 10000,
        supported: false,
      );

      final result = await instantiate(
        templateId: 't1',
        name: 'My intro',
        media: {'s1': broken, 's2': audio},
      );

      expect(_failure(result), isA<MissingTemplateMedia>());
      expect(projects.saveCount, 0);
    });

    test('rejects_an_unknown_template', () async {
      final result = await instantiate(
        templateId: 'nope',
        name: 'My intro',
        media: {'s1': video, 's2': audio},
      );

      expect(_failure(result), const TemplateNotFound('nope'));
      expect(projects.saveCount, 0);
    });
  });
}
