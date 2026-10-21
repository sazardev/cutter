import 'package:cutter/core/settings/settings_store.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/home/data/drift_home_preferences_repository.dart';
import 'package:cutter/features/home/domain/home_preferences.dart';
import 'package:cutter/features/home/domain/home_preferences_repository.dart';
import 'package:cutter/features/home/domain/project_list_query.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The domain port for the home list preferences, backed by drift.
final homePreferencesRepositoryProvider = Provider<HomePreferencesRepository>(
  (ref) => DriftHomePreferencesRepository(
    SettingsStore(ref.watch(appDatabaseProvider)),
  ),
);

/// The preferences read before the first frame; `main` overrides it.
final initialHomePreferencesProvider = Provider<HomePreferences>(
  (ref) => const HomePreferences(),
);

/// Pinned projects and the sort order; each change is saved at once.
final homePreferencesProvider =
    NotifierProvider<HomePreferencesController, HomePreferences>(
  HomePreferencesController.new,
);

/// Holds the home list preferences and persists each change.
class HomePreferencesController extends Notifier<HomePreferences> {
  @override
  HomePreferences build() => ref.watch(initialHomePreferencesProvider);

  /// Pins [projectId], or unpins it when it was pinned.
  Future<void> togglePin(String projectId) => _set(state.togglePin(projectId));

  /// Forgets what is kept about projects that are not in [existingIds] any
  /// more (pins, archive and trash entries).
  Future<void> prune(Set<String> existingIds) => _set(
        state.copyWith(
          pinnedIds: state.pinnedIds.intersection(existingIds),
          archivedIds: state.archivedIds.intersection(existingIds),
          trashedAtMs: {
            for (final e in state.trashedAtMs.entries)
              if (existingIds.contains(e.key)) e.key: e.value,
          },
        ),
      );

  /// Moves [projectId] out of the main list, keeping it.
  Future<void> archive(String projectId) => _set(state.archive(projectId));

  /// Puts an archived project back in the main list.
  Future<void> unarchive(String projectId) => _set(state.unarchive(projectId));

  /// Moves [projectId] to the trash, where it waits [trashRetention].
  Future<void> trash(String projectId) => _set(
        state.trash(projectId, DateTime.now().millisecondsSinceEpoch),
      );

  /// Takes [projectId] out of the trash.
  Future<void> restore(String projectId) => _set(state.restore(projectId));

  /// Deletes the trashed project [projectId] for good.
  Future<void> deleteForever(String projectId) async {
    await ref.read(projectRepositoryProvider).delete(projectId);
    await _set(state.restore(projectId));
  }

  /// Deletes for good every project that has been in the trash longer than
  /// [trashRetention]. Returns whether any was deleted.
  Future<bool> purgeExpired(DateTime now) async {
    final expired = state.expiredTrash(now);
    for (final id in expired) {
      await ref.read(projectRepositoryProvider).delete(id);
      await _set(state.restore(id));
    }
    return expired.isNotEmpty;
  }

  /// Orders the list by [sort].
  Future<void> setSort(ProjectSort sort) => _set(state.copyWith(sort: sort));

  Future<void> _set(HomePreferences next) async {
    if (next == state) return;
    state = next;
    try {
      await ref.read(homePreferencesRepositoryProvider).save(next);
    } on Object catch (error) {
      // The choice holds for this session; only persistence is lost.
      debugPrint('Could not save the home preferences: $error');
    }
  }
}

/// What the user typed in the search field and picked as a filter. It is
/// not persisted: the list starts unfiltered on every launch.
final projectQueryProvider = StateProvider<ProjectListQuery>(
  (ref) => const ProjectListQuery(),
);
