import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/core/engine/media_engine.dart';
import 'package:cutter/features/editor/data/built_in_template_catalog.dart';
import 'package:cutter/features/editor/data/drift_export_library.dart';
import 'package:cutter/features/editor/data/drift_media_bank.dart';
import 'package:cutter/features/editor/data/drift_project_repository.dart';
import 'package:cutter/features/editor/data/drift_version_repository.dart';
import 'package:cutter/features/editor/data/editor_dao.dart';
import 'package:cutter/features/editor/data/engine_media_inspector.dart';
import 'package:cutter/features/editor/data/media_library.dart';
import 'package:cutter/features/editor/domain/canvas_transform_use_cases.dart';
import 'package:cutter/features/editor/domain/clip_edit_use_cases.dart';
import 'package:cutter/features/editor/domain/clip_settings_use_cases.dart';
import 'package:cutter/features/editor/domain/clip_studio_use_cases.dart';
import 'package:cutter/features/editor/domain/clip_timing_use_cases.dart';
import 'package:cutter/features/editor/domain/create_project.dart';
import 'package:cutter/features/editor/domain/drawing_use_cases.dart';
import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/export_record.dart';
import 'package:cutter/features/editor/domain/import_media.dart';
import 'package:cutter/features/editor/domain/layer_use_cases.dart';
import 'package:cutter/features/editor/domain/media_bank.dart';
import 'package:cutter/features/editor/domain/project_summary.dart';
import 'package:cutter/features/editor/domain/project_version.dart';
import 'package:cutter/features/editor/domain/relink_media.dart';
import 'package:cutter/features/editor/domain/rename_project.dart';
import 'package:cutter/features/editor/domain/text_use_cases.dart';
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

/// Summaries of every stored project for the home screen. Invalidate it
/// after a write that changes a project.
final projectSummariesProvider =
    FutureProvider.autoDispose<List<ProjectSummary>>(
  (ref) => ref.watch(projectRepositoryProvider).summaries(),
);

/// The templates built into the app.
final templateCatalogProvider = Provider<TemplateCatalog>(
  (ref) => const BuiltInTemplateCatalog(),
);

/// Generates ids for new records.
final idGeneratorProvider = Provider<IdGenerator>(
  (ref) => UuidV7IdGenerator(),
);

/// The use case that creates an empty project or one laid out like a template.
final createProjectProvider = Provider<CreateProject>(
  (ref) => CreateProject(
    ref.watch(projectRepositoryProvider),
    ref.watch(templateCatalogProvider),
    ref.watch(idGeneratorProvider),
  ),
);

/// The use case that adds an empty layer to a project.
final addLayerProvider = Provider<AddLayer>(
  (ref) => AddLayer(
    ref.watch(projectRepositoryProvider),
    ref.watch(idGeneratorProvider),
  ),
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

/// The use case that swaps the picture of an image clip.
final replaceClipPictureProvider = Provider<ReplaceClipPicture>(
  (ref) => ReplaceClipPicture(ref.watch(projectRepositoryProvider)),
);

/// The use case that sets how a clip comes in and goes out.
final setClipAnimationProvider = Provider<SetClipAnimation>(
  (ref) => SetClipAnimation(ref.watch(projectRepositoryProvider)),
);

/// The use case that sets or removes a clip's filter.
final setClipFilterProvider = Provider<SetClipFilter>(
  (ref) => SetClipFilter(ref.watch(projectRepositoryProvider)),
);

/// The use case that sets a clip's adjustment values.
final setClipAdjustmentsProvider = Provider<SetClipAdjustments>(
  (ref) => SetClipAdjustments(ref.watch(projectRepositoryProvider)),
);

/// Where imported files are kept.
final mediaLibraryProvider = FutureProvider<MediaLibrary>(
  (ref) => MediaLibrary.open(),
);

/// Describes picked files with the media engine.
final mediaInspectorProvider = Provider<MediaInspector>(
  (ref) => EngineMediaInspector(
    ref.watch(mediaEngineProvider),
    ref.watch(idGeneratorProvider),
    keep: (path) async =>
        (await ref.read(mediaLibraryProvider.future)).keep(path),
  ),
);

/// The use case that places imported media on the timeline.
final importMediaProvider = Provider<ImportMedia>(
  (ref) => ImportMedia(
    ref.watch(projectRepositoryProvider),
    ref.watch(idGeneratorProvider),
  ),
);

/// The use case that points clips at another file when theirs went missing.
final relinkMediaProvider = Provider<RelinkMedia>(
  (ref) => RelinkMedia(ref.watch(projectRepositoryProvider)),
);

/// The use case that deletes a clip.
final deleteClipProvider = Provider<DeleteClip>(
  (ref) => DeleteClip(ref.watch(projectRepositoryProvider)),
);

/// The use case that duplicates a clip.
final duplicateClipProvider = Provider<DuplicateClip>(
  (ref) => DuplicateClip(
    ref.watch(projectRepositoryProvider),
    ref.watch(idGeneratorProvider),
  ),
);

/// The use case that mutes or unmutes a layer.
final setLayerMutedProvider = Provider<SetLayerMuted>(
  (ref) => SetLayerMuted(ref.watch(projectRepositoryProvider)),
);

/// The use case behind undo and redo.
final restoreProjectProvider = Provider<RestoreProject>(
  (ref) => RestoreProject(ref.watch(projectRepositoryProvider)),
);

/// The use case that changes the canvas of a project.
final setCanvasProvider = Provider<SetCanvas>(
  (ref) => SetCanvas(ref.watch(projectRepositoryProvider)),
);

/// The use case that adds a drawing over the video.
final addDrawingClipProvider = Provider<AddDrawingClip>(
  (ref) => AddDrawingClip(
    ref.watch(projectRepositoryProvider),
    ref.watch(idGeneratorProvider),
  ),
);

/// The use case that gives a drawing clip new strokes.
final setClipDrawingProvider = Provider<SetClipDrawing>(
  (ref) => SetClipDrawing(ref.watch(projectRepositoryProvider)),
);

/// The use case that adds a text over the video.
final addTextClipProvider = Provider<AddTextClip>(
  (ref) => AddTextClip(
    ref.watch(projectRepositoryProvider),
    ref.watch(idGeneratorProvider),
  ),
);

/// The use case that changes the words or look of a text.
final setClipTextProvider = Provider<SetClipText>(
  (ref) => SetClipText(ref.watch(projectRepositoryProvider)),
);

/// The use case that places the picture of a clip.
final setClipTransformProvider = Provider<SetClipTransform>(
  (ref) => SetClipTransform(ref.watch(projectRepositoryProvider)),
);

/// The domain port for saved versions, backed by drift.
final versionRepositoryProvider = Provider<VersionRepository>(
  (ref) => DriftVersionRepository(ref.watch(appDatabaseProvider)),
);

/// The use case that saves a named version.
final saveVersionProvider = Provider<SaveVersion>(
  (ref) => SaveVersion(
    ref.watch(projectRepositoryProvider),
    ref.watch(versionRepositoryProvider),
    ref.watch(idGeneratorProvider),
  ),
);

/// The use case that reorders the layers of a project.
final reorderLayersProvider = Provider<ReorderLayers>(
  (ref) => ReorderLayers(ref.watch(projectRepositoryProvider)),
);

/// The use case that renames a project.
final renameProjectProvider = Provider<RenameProject>(
  (ref) => RenameProject(ref.watch(projectRepositoryProvider)),
);

/// The use case that restores a saved version.
final restoreVersionProvider = Provider<RestoreVersion>(
  (ref) => RestoreVersion(
    ref.watch(projectRepositoryProvider),
    ref.watch(versionRepositoryProvider),
  ),
);

/// The saved versions of a project, the newest first.
final projectVersionsProvider =
    FutureProvider.autoDispose.family<List<ProjectVersion>, String>(
  (ref, projectId) =>
      ref.watch(versionRepositoryProvider).versionsOf(projectId),
);

/// The use case that changes the speed of a clip.
final setClipSpeedProvider = Provider<SetClipSpeed>(
  (ref) => SetClipSpeed(ref.watch(projectRepositoryProvider)),
);

/// The use case that fades the sound of a clip.
final setClipFadesProvider = Provider<SetClipFades>(
  (ref) => SetClipFades(ref.watch(projectRepositoryProvider)),
);

/// The use case that crops the picture of a clip.
final setClipCropProvider = Provider<SetClipCrop>(
  (ref) => SetClipCrop(ref.watch(projectRepositoryProvider)),
);

/// The use case that sets how long an image shows.
final setImageDurationProvider = Provider<SetImageDuration>(
  (ref) => SetImageDuration(ref.watch(projectRepositoryProvider)),
);

/// The rendered videos, backed by drift.
final exportLibraryProvider = Provider<ExportLibrary>(
  (ref) => DriftExportLibrary(ref.watch(appDatabaseProvider)),
);

/// Every rendered video still on the device, the newest first.
final exportRecordsProvider = FutureProvider.autoDispose<List<ExportRecord>>(
  (ref) => ref.watch(exportLibraryProvider).all(),
);

/// The media banks, backed by drift.
final mediaBankProvider = Provider<MediaBank>(
  (ref) => DriftMediaBank(ref.watch(appDatabaseProvider)),
);

/// The bank of a project, the newest first.
final projectMediaProvider =
    FutureProvider.autoDispose.family<List<MediaItem>, String>(
  (ref, projectId) => ref.watch(mediaBankProvider).itemsOf(projectId),
);

/// Files imported into other projects, for reuse.
final recentMediaProvider =
    FutureProvider.autoDispose.family<List<MediaItem>, String>(
  (ref, projectId) =>
      ref.watch(mediaBankProvider).recent(exceptProjectId: projectId),
);

/// The controller holding the editor screen state.
final editorControllerProvider =
    NotifierProvider<EditorController, AsyncValue<EditorUiState>>(
  EditorController.new,
);
