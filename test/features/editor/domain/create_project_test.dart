import 'package:cutter/features/editor/data/built_in_template_catalog.dart';
import 'package:cutter/features/editor/domain/canvas.dart';
import 'package:cutter/features/editor/domain/create_project.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_editor_ports.dart';

void main() {
  late InMemoryProjectRepository repository;
  late CreateProject createProject;

  setUp(() {
    repository = InMemoryProjectRepository();
    createProject = CreateProject(
      repository,
      const BuiltInTemplateCatalog(),
      SequentialIdGenerator(),
    );
  });

  test('creates_and_saves_an_empty_project', () async {
    final result = await createProject(name: '  My video ');

    final project = (result as Ok<Project>).value;
    expect(project.name, 'My video');
    expect(project.layers, isEmpty);
    expect(repository.projects[project.id], project);
  });

  test('rejects_a_blank_name_without_saving', () async {
    final result = await createProject(name: '   ');

    expect(result, const Err<Project>(EmptyName()));
    expect(repository.saveCount, 0);
  });

  test('lays_out_the_layers_of_a_template_without_clips', () async {
    final result = await createProject(
      name: 'Story',
      templateId: BuiltInTemplateIds.verticalStory,
    );

    final project = (result as Ok<Project>).value;
    expect(project.templateId, BuiltInTemplateIds.verticalStory);
    expect(
      project.layers.map((layer) => layer.kind),
      [MediaKind.video, MediaKind.audio],
    );
    expect(project.layers.every((layer) => layer.clips.isEmpty), isTrue);
    expect(project.layers.map((layer) => layer.id).toSet(), hasLength(2));
  });

  test('rejects_an_unknown_template_without_saving', () async {
    final result = await createProject(name: 'Story', templateId: 'nope');

    expect(result, const Err<Project>(TemplateNotFound('nope')));
    expect(repository.saveCount, 0);
  });

  test('the_built_in_catalog_finds_every_template_it_lists', () async {
    const catalog = BuiltInTemplateCatalog();
    final all = await catalog.all();

    expect(all, hasLength(3));
    for (final template in all) {
      expect(await catalog.find(template.id), template);
    }
    expect(await catalog.find('nope'), isNull);
  });

  test('creates the project on the chosen canvas', () async {
    const canvas = Canvas(width: 1920, height: 1080, fps: 60);

    final result = await createProject(name: 'Wide', canvas: canvas);

    expect((result as Ok<Project>).value.canvas, canvas);
  });
}
