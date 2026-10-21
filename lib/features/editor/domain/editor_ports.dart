import 'package:cutter/features/editor/domain/preset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/domain/project_summary.dart';
import 'package:cutter/features/editor/domain/template.dart';

/// Storage of projects, owned by the domain and implemented at the edge.
abstract interface class ProjectRepository {
  /// The project with [id], or null when it is unknown.
  Future<Project?> find(String id);

  /// Stores [project], replacing any stored project with the same id.
  Future<void> save(Project project);

  /// A summary of every stored project, the most recently saved first.
  Future<List<ProjectSummary>> summaries();

  /// Removes the project with [id] with its layers, clips and saved
  /// versions. Videos already exported stay in the library. Nothing happens
  /// when the id is unknown.
  Future<void> delete(String id);
}

/// Storage of presets, owned by the domain and implemented at the edge.
abstract interface class PresetRepository {
  /// Every saved preset.
  Future<List<Preset>> all();

  /// The preset with [id], or null when it is unknown.
  Future<Preset?> find(String id);

  /// Stores [preset], replacing any stored preset with the same id.
  Future<void> save(Preset preset);
}

/// Source of templates, owned by the domain and implemented at the edge.
abstract interface class TemplateCatalog {
  /// Every available template.
  Future<List<Template>> all();

  /// The template with [id], or null when it is unknown.
  Future<Template?> find(String id);
}

/// Produces identifiers for new entities.
// ignore: one_member_abstracts
abstract interface class IdGenerator {
  /// A new unique id; every call returns a different value.
  String next();
}
