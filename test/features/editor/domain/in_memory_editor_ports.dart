import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/preset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/domain/project_summary.dart';
import 'package:cutter/features/editor/domain/project_version.dart';
import 'package:cutter/features/editor/domain/template.dart';

/// Project storage in a map; [saveCount] lets tests assert that a rejected
/// command saved nothing.
class InMemoryProjectRepository implements ProjectRepository {
  InMemoryProjectRepository([Iterable<Project> initial = const []]) {
    for (final project in initial) {
      projects[project.id] = project;
    }
  }

  /// The stored projects by id.
  final Map<String, Project> projects = {};

  /// How many times [save] was called.
  int saveCount = 0;

  @override
  Future<Project?> find(String id) async => projects[id];

  @override
  Future<void> save(Project project) async {
    saveCount++;
    projects[project.id] = project;
  }

  @override
  Future<void> delete(String id) async => projects.remove(id);

  @override
  Future<List<ProjectSummary>> summaries() async => [
        for (final project in projects.values)
          ProjectSummary(
            id: project.id,
            name: project.name,
            layerCount: project.layers.length,
            clipCount: project.layers.fold(
              0,
              (count, layer) => count + layer.clips.length,
            ),
            durationMs: project.durationMs,
            updatedAtMs: 0,
          ),
      ];
}

/// Preset storage in a map, listed in insertion order.
class InMemoryPresetRepository implements PresetRepository {
  InMemoryPresetRepository([Iterable<Preset> initial = const []]) {
    for (final preset in initial) {
      presets[preset.id] = preset;
    }
  }

  /// The stored presets by id.
  final Map<String, Preset> presets = {};

  @override
  Future<List<Preset>> all() async => presets.values.toList();

  @override
  Future<Preset?> find(String id) async => presets[id];

  @override
  Future<void> save(Preset preset) async {
    presets[preset.id] = preset;
  }
}

/// Template catalog backed by a map.
class InMemoryTemplateCatalog implements TemplateCatalog {
  InMemoryTemplateCatalog([Iterable<Template> initial = const []]) {
    for (final template in initial) {
      templates[template.id] = template;
    }
  }

  /// The available templates by id.
  final Map<String, Template> templates = {};

  @override
  Future<List<Template>> all() async => templates.values.toList();

  @override
  Future<Template?> find(String id) async => templates[id];
}

/// Returns 'id-1', 'id-2', ... so tests can predict new ids.
class SequentialIdGenerator implements IdGenerator {
  int _counter = 0;

  @override
  String next() {
    _counter++;
    return 'id-$_counter';
  }
}

/// Project 'p1': video layer v1 with clips c1 and c2, audio layer a1 with
/// clip m1 at volume 0.8.
Project buildFixtureProject() {
  const first = Clip(
    id: 'c1',
    layerId: 'v1',
    assetId: 'asset-video',
    sourceUri: 'file:///video.mp4',
    kind: MediaKind.video,
    startMs: 0,
    inPointMs: 0,
    outPointMs: 4000,
    sourceDurationMs: 10000,
  );
  const second = Clip(
    id: 'c2',
    layerId: 'v1',
    assetId: 'asset-video',
    sourceUri: 'file:///video.mp4',
    kind: MediaKind.video,
    startMs: 6000,
    inPointMs: 0,
    outPointMs: 2000,
    sourceDurationMs: 10000,
  );
  const music = Clip(
    id: 'm1',
    layerId: 'a1',
    assetId: 'asset-music',
    sourceUri: 'file:///music.mp3',
    kind: MediaKind.audio,
    startMs: 0,
    inPointMs: 0,
    outPointMs: 8000,
    sourceDurationMs: 10000,
    volume: 0.8,
  );
  return Project(
    id: 'p1',
    name: 'Fixture',
    layers: [
      Layer(
        id: 'v1',
        name: 'Video',
        kind: MediaKind.video,
        clips: const [first, second],
      ),
      Layer(
        id: 'a1',
        name: 'Music',
        kind: MediaKind.audio,
        clips: const [music],
      ),
    ],
  );
}

/// Version storage in maps, newest first, with the snapshots kept whole.
class InMemoryVersionRepository implements VersionRepository {
  /// The stored versions, in the order they were saved.
  final List<ProjectVersion> versions = [];

  /// The snapshots by version id.
  final Map<String, Project> snapshots = {};

  @override
  Future<List<ProjectVersion>> versionsOf(String projectId) async => [
        for (final version in versions.reversed)
          if (version.projectId == projectId) version,
      ];

  @override
  Future<void> save(ProjectVersion version, Project snapshot) async {
    versions.add(version);
    snapshots[version.id] = snapshot;
  }

  @override
  Future<Project?> snapshotOf(String versionId) async => snapshots[versionId];
}
