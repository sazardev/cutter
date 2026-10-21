import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/features/editor/data/drift_project_repository.dart';
import 'package:cutter/features/editor/data/editor_dao.dart';
import 'package:cutter/features/editor/domain/clip_settings_use_cases.dart';
import 'package:cutter/features/editor/domain/clip_timing_use_cases.dart';
import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/presentation/editor_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Time-ordered UUID v7 ids for records created on the device.
class UuidV7IdGenerator implements IdGenerator {
  /// Creates a generator backed by the `uuid` package.
  UuidV7IdGenerator() : _uuid = const Uuid();

  final Uuid _uuid;

  @override
  String next() => _uuid.v7();
}

/// The opened database. `main` overrides it; reading it before that is a
/// programmer error.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw StateError(
    'appDatabaseProvider must be overridden with the opened database.',
  ),
);

final _driftProjectRepositoryProvider = Provider<DriftProjectRepository>(
  (ref) => DriftProjectRepository(EditorDao(ref.watch(appDatabaseProvider))),
);

/// The domain port for stored projects, backed by drift.
final projectRepositoryProvider = Provider<ProjectRepository>(
  (ref) => ref.watch(_driftProjectRepositoryProvider),
);

/// The id of the project the editor opens, or null when none is stored.
final editorProjectProvider = FutureProvider<String?>(
  (ref) => ref.watch(_driftProjectRepositoryProvider).firstProjectId(),
);

/// Generates ids for new records.
final idGeneratorProvider = Provider<IdGenerator>(
  (ref) => UuidV7IdGenerator(),
);

/// The use case that splits a clip at the playhead.
final splitClipProvider = Provider<SplitClip>(
  (ref) => SplitClip(
    ref.watch(projectRepositoryProvider),
    ref.watch(idGeneratorProvider),
  ),
);

/// The use case that trims the in and out points of a clip.
final trimClipProvider = Provider<TrimClip>(
  (ref) => TrimClip(ref.watch(projectRepositoryProvider)),
);

/// The use case that moves a clip in time or across layers.
final moveClipProvider = Provider<MoveClip>(
  (ref) => MoveClip(ref.watch(projectRepositoryProvider)),
);

/// The use case that reverses a clip's playback direction.
final setClipReverseProvider = Provider<SetClipReverse>(
  (ref) => SetClipReverse(ref.watch(projectRepositoryProvider)),
);

/// The use case that sets a clip's volume.
final setClipVolumeProvider = Provider<SetClipVolume>(
  (ref) => SetClipVolume(ref.watch(projectRepositoryProvider)),
);

/// The use case that sets or removes a clip's filter.
final setClipFilterProvider = Provider<SetClipFilter>(
  (ref) => SetClipFilter(ref.watch(projectRepositoryProvider)),
);

/// The use case that sets a clip's adjustment values.
final setClipAdjustmentsProvider = Provider<SetClipAdjustments>(
  (ref) => SetClipAdjustments(ref.watch(projectRepositoryProvider)),
);

/// The controller holding the editor screen state.
final editorControllerProvider =
    NotifierProvider<EditorController, AsyncValue<EditorUiState>>(
  EditorController.new,
);
