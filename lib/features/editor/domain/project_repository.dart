// Domain port for loading and saving editor projects.
import 'package:cutter/features/editor/domain/project.dart';

/// Storage port for editor projects, owned by the domain and implemented in
/// the data layer.
abstract interface class ProjectRepository {
  /// Loads the project with [id], or returns null when the id is unknown.
  Future<Project?> load(String id);

  /// Persists [project] atomically, replacing its previous stored state.
  Future<void> save(Project project);
}
