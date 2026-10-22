import 'dart:async';
import 'dart:io';

import 'package:cutter/core/engine/media_engine.dart';
import 'package:cutter/features/editor/data/engine_timeline.dart';
import 'package:cutter/features/editor/domain/animation_preset.dart';
import 'package:cutter/features/editor/domain/canvas.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/clip_crop.dart';
import 'package:cutter/features/editor/domain/clip_drawing.dart';
import 'package:cutter/features/editor/domain/clip_text.dart';
import 'package:cutter/features/editor/domain/clip_transform.dart';
import 'package:cutter/features/editor/domain/clip_transition.dart';
import 'package:cutter/features/editor/domain/edit_history.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/import_limits.dart';
import 'package:cutter/features/editor/domain/import_media.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/media_bank.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/domain/project_version.dart';
import 'package:cutter/features/editor/domain/relink_media.dart';
import 'package:cutter/features/editor/presentation/animation_preset_providers.dart';
import 'package:cutter/features/editor/presentation/checkpoint_labels.dart';
import 'package:cutter/features/editor/presentation/drawing/drawing_painter.dart';
import 'package:cutter/features/editor/presentation/edit_log.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/layout/editor_layout.dart';
import 'package:cutter/features/editor/presentation/project_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Everything the editor screen shows besides playback: the project, the
/// selected clip, what can be undone and the failure of the last rejected
/// action.
class EditorUiState {
  /// Creates the editor state for [project].
  const EditorUiState({
    required this.project,
    this.selectedClipId,
    this.failure,
    this.canUndo = false,
    this.canRedo = false,
    this.importing = false,
  });

  /// The project being edited.
  final Project project;

  /// The id of the selected clip, or null when nothing is selected.
  final String? selectedClipId;

  /// The failure of the last rejected action, or null when there is none.
  final EditorFailure? failure;

  /// Whether there is an edit to undo.
  final bool canUndo;

  /// Whether there is an undone edit to redo.
  final bool canRedo;

  /// Whether picked files are being read.
  final bool importing;

  /// The selected clip, or null.
  Clip? get selectedClip {
    final id = selectedClipId;
    return id == null ? null : project.clipById(id);
  }

  /// The layer of the selected clip, or null.
  Layer? get selectedLayer {
    final id = selectedClipId;
    return id == null ? null : project.layerOfClip(id);
  }

  /// Returns a copy with the given fields replaced; nullable fields are set
  /// through a callback so that null can be assigned explicitly.
  EditorUiState copyWith({
    Project? project,
    String? Function()? selectedClipId,
    EditorFailure? Function()? failure,
    bool? canUndo,
    bool? canRedo,
    bool? importing,
  }) {
    return EditorUiState(
      project: project ?? this.project,
      selectedClipId:
          selectedClipId != null ? selectedClipId() : this.selectedClipId,
      failure: failure != null ? failure() : this.failure,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      importing: importing ?? this.importing,
    );
  }
}

/// What came of importing picked files.
class ImportOutcome {
  /// Creates the outcome.
  const ImportOutcome({
    required this.imported,
    required this.rejected,
    this.canvasChangedTo,
    this.issues = const [],
    this.notices = const [],
  });

  /// The shape the project took from its first picture, if it changed.
  final CanvasPreset? canvasChangedTo;

  /// How many files became clips.
  final int imported;

  /// The paths of the files that were left out.
  final List<String> rejected;

  /// Each file that was left out, with why.
  final List<ImportIssue> issues;

  /// Warnings about files that were imported anyway.
  final List<ImportNotice> notices;

  /// Whether there is anything to tell the user about.
  bool get hasReport => issues.isNotEmpty || notices.isNotEmpty;
}

/// The longest side, in pixels, of the picture a drawing is rendered to.
const _drawingMaxSide = 1920;

/// Runs the domain use cases for the editor screen. Every accepted edit is
/// saved at once (autosave) and can be undone for as long as the editor is
/// open.
class EditorController extends Notifier<AsyncValue<EditorUiState>> {
  EditHistory _history = EditHistory();

  /// The last text edit, to join a burst of them into one undo step.
  ({String clipId, int atMs})? _lastTextEdit;
  static const _textBurstMs = 1500;
  CheckpointLabels? _labels;
  int _lastCheckpointMs = 0;

  @override
  AsyncValue<EditorUiState> build() => const AsyncValue.loading();

  /// Loads the project with [projectId] from the local database. With
  /// [labels] the editor also keeps automatic restore points (see
  /// [ProjectVersion]); without them it only saves what the user asks.
  Future<void> load(String projectId, {CheckpointLabels? labels}) async {
    _labels = labels;
    _history = EditHistory();
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final project = await ref.read(projectRepositoryProvider).find(projectId);
      if (project == null) {
        throw StateError('Project $projectId was not found.');
      }
      return EditorUiState(project: await _dropEmptyLayers(project));
    });
    final loaded = state.valueOrNull?.project;
    if (loaded != null) {
      await _repairSourceSizes(loaded);
      await _openCheckpoints(loaded.id);
    }
  }

  /// Learns when the last restore point was saved and, for a project that
  /// has none, saves its first one: from then on there is always a point to
  /// go back to.
  Future<void> _openCheckpoints(String projectId) async {
    final labels = _labels;
    if (labels == null) return;
    final versions =
        await ref.read(versionRepositoryProvider).versionsOf(projectId);
    if (versions.isEmpty) {
      await _checkpoint(labels.start);
    } else {
      _lastCheckpointMs = versions.first.createdAtMs;
    }
  }

  /// Saves the current state as a restore point called [name], without
  /// touching what the screen shows.
  Future<void> _checkpoint(String name) async {
    final current = state.valueOrNull;
    if (current == null) return;
    _lastCheckpointMs = DateTime.now().millisecondsSinceEpoch;
    final result = await ref
        .read(saveVersionProvider)
        .call(projectId: current.project.id, name: name);
    if (result is Ok<ProjectVersion>) {
      ref.invalidate(projectVersionsProvider(current.project.id));
    }
  }

  /// Saves a restore point when [autoCheckpointInterval] has passed since the
  /// last one: a bad edit is never more than that far from a way back.
  void _checkpointIfDue() {
    final labels = _labels;
    if (labels == null) return;
    final now = DateTime.now();
    final due = now.millisecondsSinceEpoch - _lastCheckpointMs >=
        autoCheckpointInterval.inMilliseconds;
    if (due) unawaited(_checkpoint(labels.auto(now)));
  }

  /// Measures the pictures of clips stored before their source size was
  /// kept (schema 3 and older) and stores it, so they can be selected and
  /// framed in the preview. Not an edit: nothing goes into undo.
  Future<void> _repairSourceSizes(Project project) async {
    final missing = <String, Clip>{};
    for (final layer in project.layers) {
      for (final clip in layer.clips) {
        if (clip.kind != MediaKind.audio && clip.sourceWidth <= 0) {
          missing[clip.id] = clip;
        }
      }
    }
    if (missing.isEmpty) return;
    final inspector = ref.read(mediaInspectorProvider);
    final sizes = <String, (int, int)>{};
    for (final clip in missing.values) {
      final asset = await inspector.measure(filePathOf(clip.sourceUri));
      if (asset != null) sizes[clip.id] = asset;
    }
    final current = state.valueOrNull;
    if (sizes.isEmpty || current == null) return;
    final repaired = current.project.withLayers([
      for (final layer in current.project.layers)
        layer.withClips([
          for (final clip in layer.clips)
            if (sizes[clip.id] case (final w, final h))
              clip.copyWith(sourceWidth: w, sourceHeight: h)
            else
              clip,
        ]),
    ]);
    await ref.read(projectRepositoryProvider).save(repaired);
    state = AsyncValue.data(current.copyWith(project: repaired));
  }

  /// Selects the clip with [id], or clears the selection when null.
  void selectClip(String? id) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(
      current.copyWith(selectedClipId: () => id, failure: () => null),
    );
  }

  /// Forgets the failure of the last rejected action once it was shown.
  void clearFailure() {
    final current = state.valueOrNull;
    if (current == null || current.failure == null) return;
    state = AsyncValue.data(current.copyWith(failure: () => null));
  }

  /// Puts the screen in its error state when the project could not be read
  /// at all, so the page can offer a retry.
  void reportError(Object error, StackTrace stackTrace) {
    state = AsyncValue.error(error, stackTrace);
  }

  /// True when the selected clip can be split at [playheadMs].
  bool canSplitAt(int playheadMs) {
    final clip = state.valueOrNull?.selectedClip;
    if (clip == null) return false;
    return clip.range.containsStrictly(playheadMs);
  }

  /// Reads the files at [paths] and places the playable ones on the
  /// timeline; the others are reported back, never dropped silently.
  ///
  /// Every playable file goes into the project's media bank; with
  /// [toTimeline] it is also placed, where its kind belongs: pictures at the
  /// end of the sequence, sound at the playhead.
  Future<ImportOutcome> importFiles(
    List<String> paths, {
    required int atMs,
    ImportPlacement placement = ImportPlacement.append,
    bool toTimeline = true,
  }) async {
    final current = state.valueOrNull;
    if (current == null || paths.isEmpty) {
      return const ImportOutcome(imported: 0, rejected: []);
    }
    state = AsyncValue.data(current.copyWith(importing: true));
    final inspector = ref.read(mediaInspectorProvider);
    final assets = <MediaAsset>[];
    final rejected = <String>[];
    final issues = <ImportIssue>[];
    final notices = <ImportNotice>[];
    for (final path in paths) {
      final asset = await inspector.inspect(path);
      // A file too short to be a clip is left out with its own reason; it
      // never takes the rest of the import down with it.
      if (asset.supported && asset.durationMs >= minClipDurationMs) {
        assets.add(asset);
        for (final kind in noticesFor(
          width: asset.width,
          height: asset.height,
          durationMs: asset.durationMs,
          sizeBytes: asset.sizeBytes,
        )) {
          notices.add(ImportNotice(path, kind));
        }
      } else {
        rejected.add(path);
        issues.add(
          ImportIssue(
            path,
            asset.supported
                ? ImportIssueKind.tooShort
                : asset.issue ?? ImportIssueKind.unreadable,
          ),
        );
      }
    }
    final latest = state.valueOrNull ?? current;
    state = AsyncValue.data(latest.copyWith(importing: false));
    if (assets.isEmpty) {
      return ImportOutcome(imported: 0, rejected: rejected, issues: issues);
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await ref.read(mediaBankProvider).add([
      for (final asset in assets)
        MediaItem(
          id: ref.read(idGeneratorProvider).next(),
          projectId: latest.project.id,
          path: asset.uri,
          kind: asset.kind,
          durationMs: asset.durationMs,
          width: asset.width,
          height: asset.height,
          hasAudio: asset.audioPresent,
          addedAtMs: now,
        ),
    ]);
    ref.invalidate(projectMediaProvider(latest.project.id));
    if (!toTimeline) {
      return ImportOutcome(
        imported: assets.length,
        rejected: rejected,
        issues: issues,
        notices: notices,
      );
    }

    final before = latest.project;
    final wasEmpty = before.layers.every((l) => l.clips.isEmpty);
    final accepted = await _run(
      'import',
      (project) => ref.read(importMediaProvider).call(
            projectId: project.id,
            assets: assets,
            atMs: atMs,
            placement: placement,
          ),
    );
    if (accepted) {
      final after = state.valueOrNull!.project;
      final added = _newClipIds(before, after);
      if (added.isNotEmpty) selectClip(added.last);
      // The first picture of an empty project gives it its shape, as long as
      // the project still has the default canvas.
      final first =
          assets.where((a) => a.kind != MediaKind.audio && a.width > 0);
      if (wasEmpty && first.isNotEmpty && after.canvas == defaultCanvas) {
        final shape = _closestPreset(first.first.width / first.first.height);
        if (shape != CanvasPreset.portrait) {
          await setCanvas(shape.canvas(fps: after.canvas.fps));
          return ImportOutcome(
            imported: assets.length,
            rejected: rejected,
            canvasChangedTo: shape,
            issues: issues,
            notices: notices,
          );
        }
      }
    }
    return ImportOutcome(
      imported: accepted ? assets.length : 0,
      rejected: rejected,
      issues: issues,
      notices: notices,
    );
  }

  /// Points the clips whose file [oldUri] is missing at the file at [path],
  /// keeping their places and trims. The new file is copied into the app
  /// like any import. Returns whether it fitted; when it did not, nothing
  /// changed and the copy is removed.
  Future<RelinkCheck> relinkMedia(String oldUri, String path) async {
    final current = state.valueOrNull;
    if (current == null) return RelinkCheck.notUsed;
    final asset = await ref.read(mediaInspectorProvider).inspect(path);
    final check = relinkCheck(current.project, oldUri, asset);
    if (check != RelinkCheck.ok) {
      await _forgetCopy(path, asset);
      return check;
    }
    final done = await _run(
      'relink',
      (project) => ref.read(relinkMediaProvider).call(
            projectId: project.id,
            oldUri: oldUri,
            asset: asset,
          ),
    );
    return done ? RelinkCheck.ok : RelinkCheck.unreadable;
  }

  /// Removes the copy the inspector made of [path] when it was not used.
  Future<void> _forgetCopy(String path, MediaAsset asset) async {
    if (!asset.supported || asset.uri == path) return;
    final library = await ref.read(mediaLibraryProvider.future);
    if (!library.contains(asset.uri)) return;
    try {
      await File(asset.uri).delete();
    } on FileSystemException {
      // A leftover copy costs space only.
    }
  }

  /// Places files of the media bank on the timeline: pictures at the end of
  /// the sequence (or on a new layer at [atMs] for an overlay), sound at
  /// [atMs]. Returns whether they were placed.
  Future<bool> placeFromBank(
    List<MediaItem> items, {
    required int atMs,
    ImportPlacement placement = ImportPlacement.append,
  }) async {
    if (items.isEmpty) return false;
    final before = state.valueOrNull?.project;
    final ids = ref.read(idGeneratorProvider);
    final ok = await _run(
      'place from bank',
      (project) => ref.read(importMediaProvider).call(
            projectId: project.id,
            assets: [for (final item in items) item.toAsset(ids.next())],
            atMs: atMs,
            placement: placement,
          ),
    );
    final after = state.valueOrNull?.project;
    if (ok && before != null && after != null) {
      final added = _newClipIds(before, after);
      if (added.isNotEmpty) selectClip(added.last);
    }
    return ok;
  }

  /// Splits the selected clip at [playheadMs].
  Future<void> splitAt(int playheadMs) async {
    final clip = state.valueOrNull?.selectedClip;
    if (clip == null) return;
    await _run(
      'split',
      (project) => ref.read(splitClipProvider).call(
            projectId: project.id,
            clipId: clip.id,
            atMs: playheadMs,
          ),
    );
  }

  /// Deletes the selected clip. On the main layer, the clips after it move
  /// back to close the gap.
  Future<void> deleteSelected() async {
    final current = state.valueOrNull;
    final clip = current?.selectedClip;
    final layer = current?.selectedLayer;
    if (current == null || clip == null || layer == null) return;
    final ripple = _isMainLayer(current.project, layer);
    final ok = await _run(
      'delete',
      (project) => ref.read(deleteClipProvider).call(
            projectId: project.id,
            clipId: clip.id,
            ripple: ripple,
          ),
    );
    if (ok) selectClip(null);
  }

  /// Duplicates the selected clip right after itself and selects the copy.
  Future<void> duplicateSelected() async {
    final clip = state.valueOrNull?.selectedClip;
    if (clip == null) return;
    final before = state.valueOrNull!.project;
    final ok = await _run(
      'duplicate',
      (project) => ref.read(duplicateClipProvider).call(
            projectId: project.id,
            clipId: clip.id,
          ),
    );
    if (!ok) return;
    final added = _newClipIds(before, state.valueOrNull!.project);
    if (added.isNotEmpty) selectClip(added.single);
  }

  /// Moves clip [clipId] to [startMs] on layer [layerId].
  Future<void> moveClip(String clipId, String layerId, int startMs) async {
    await _run(
      'move',
      (project) => ref.read(moveClipProvider).call(
            projectId: project.id,
            clipId: clipId,
            targetLayerId: layerId,
            startMs: startMs < 0 ? 0 : startMs,
          ),
    );
  }

  /// Trims clip [clipId] to [inPointMs]..[outPointMs] of its source.
  Future<void> trimClip(
    String clipId, {
    required int inPointMs,
    required int outPointMs,
  }) async {
    await _run(
      'trim',
      (project) => ref.read(trimClipProvider).call(
            projectId: project.id,
            clipId: clipId,
            inPointMs: inPointMs,
            outPointMs: outPointMs,
          ),
    );
  }

  /// Flips the reverse flag of the selected clip.
  Future<void> toggleReverse() async {
    final clip = state.valueOrNull?.selectedClip;
    if (clip == null) return;
    await _run(
      'reverse',
      (project) => ref.read(setClipReverseProvider).call(
            projectId: project.id,
            clipId: clip.id,
            enabled: !clip.reversed,
          ),
    );
  }

  /// Sets the volume of the selected clip.
  Future<void> setClipVolume(double value) async {
    final clip = state.valueOrNull?.selectedClip;
    if (clip == null) return;
    await _run(
      'volume',
      (project) => ref.read(setClipVolumeProvider).call(
            projectId: project.id,
            clipId: clip.id,
            volume: value,
          ),
    );
  }

  /// Mutes or unmutes layer [layerId].
  Future<void> setLayerMuted(String layerId, {required bool muted}) async {
    await _run(
      'mute layer',
      (project) => ref.read(setLayerMutedProvider).call(
            projectId: project.id,
            layerId: layerId,
            muted: muted,
          ),
    );
  }

  /// Sets the filter of the selected clip; null removes it.
  Future<void> setFilter(String? filterId) async {
    final clip = state.valueOrNull?.selectedClip;
    if (clip == null) return;
    await _run(
      'filter',
      (project) => ref.read(setClipFilterProvider).call(
            projectId: project.id,
            clipId: clip.id,
            filterId: filterId,
          ),
    );
  }

  /// Sets how the selected clip comes in and goes out; a null id removes
  /// that animation.
  Future<void> setAnimation({
    String? animIn,
    int animInMs = 0,
    String? animOut,
    int animOutMs = 0,
  }) async {
    final clip = state.valueOrNull?.selectedClip;
    if (clip == null) return;
    await _run(
      'animation',
      (project) => ref.read(setClipAnimationProvider).call(
            projectId: project.id,
            clipId: clip.id,
            animIn: animIn,
            animInMs: animInMs,
            animOut: animOut,
            animOutMs: animOutMs,
          ),
    );
  }

  /// Gives [preset]'s entrance and exit to the selected clip, or to every
  /// clip of its layer when [wholeLayer] is set. One edit, one undo.
  Future<void> applyAnimationPreset(
    AnimationPreset preset, {
    bool wholeLayer = false,
  }) async {
    final editor = state.valueOrNull;
    final clip = editor?.selectedClip;
    if (editor == null || clip == null) return;
    final layer = editor.project.layerOfClip(clip.id);
    final ids = wholeLayer && layer != null
        ? [for (final c in layer.clips) c.id]
        : [clip.id];
    await _run(
      'animation preset',
      (project) => ref.read(applyAnimationPresetProvider).call(
            projectId: project.id,
            clipIds: ids,
            preset: preset,
          ),
    );
  }

  /// Joins the selected clip to the one before it with [kind], [durationMs]
  /// long on each side. One edit, one undo.
  Future<void> applyTransition(
    TransitionKind kind,
    int durationMs, {
    bool fadeSound = true,
  }) async {
    final clip = state.valueOrNull?.selectedClip;
    if (clip == null) return;
    await _run(
      'transition',
      (project) => ref.read(applyTransitionProvider).call(
            projectId: project.id,
            clipId: clip.id,
            kind: kind,
            durationMs: durationMs,
            fadeSound: fadeSound,
          ),
    );
  }

  /// Takes the transition off the join of the selected clip with the one
  /// before it.
  Future<void> removeTransition() async {
    final clip = state.valueOrNull?.selectedClip;
    if (clip == null) return;
    await _run(
      'remove transition',
      (project) => ref.read(removeTransitionProvider).call(
            projectId: project.id,
            clipId: clip.id,
          ),
    );
  }

  /// Saves the adjustments of the selected clip.
  Future<void> setAdjustments(Map<String, double> adjustments) async {
    final clip = state.valueOrNull?.selectedClip;
    if (clip == null) return;
    await _run(
      'adjust',
      (project) => ref.read(setClipAdjustmentsProvider).call(
            projectId: project.id,
            clipId: clip.id,
            adjustments: adjustments,
          ),
    );
  }

  /// Plays clip [clipId] at [speed].
  Future<void> setSpeed(String clipId, double speed) async {
    await _run(
      'speed',
      (project) => ref
          .read(setClipSpeedProvider)
          .call(projectId: project.id, clipId: clipId, speed: speed),
    );
  }

  /// Fades the sound of clip [clipId] in and out.
  Future<void> setFades(
    String clipId, {
    required int inMs,
    required int outMs,
  }) async {
    await _run(
      'fades',
      (project) => ref.read(setClipFadesProvider).call(
            projectId: project.id,
            clipId: clipId,
            inMs: inMs,
            outMs: outMs,
          ),
    );
  }

  /// Keeps only [crop] of the picture of clip [clipId].
  Future<void> setCrop(String clipId, ClipCrop crop) async {
    await _run(
      'crop',
      (project) => ref
          .read(setClipCropProvider)
          .call(projectId: project.id, clipId: clipId, crop: crop),
    );
  }

  /// Makes image clip [clipId] last [durationMs].
  Future<void> setImageDuration(String clipId, int durationMs) async {
    await _run(
      'image duration',
      (project) => ref.read(setImageDurationProvider).call(
            projectId: project.id,
            clipId: clipId,
            durationMs: durationMs,
          ),
    );
  }

  /// Balances clip [clipId]'s brightness, contrast and saturation from its
  /// own frames, measured by the engine. Returns false when it could not.
  Future<bool> autoAdjust(String clipId) async {
    final clip = state.valueOrNull?.project.clipById(clipId);
    if (clip == null || clip.kind == MediaKind.audio) return false;
    final SuggestedAdjustments suggestion;
    try {
      suggestion = await ref.read(mediaEngineProvider).suggestAdjustments(
            filePathOf(clip.sourceUri),
            fromMs: clip.inPointMs,
            toMs: clip.kind == MediaKind.image ? 1 : clip.outPointMs,
          );
    } on Object {
      return false;
    }
    final selected = state.valueOrNull?.selectedClipId;
    selectClip(clipId);
    await setAdjustments({
      'brightness': suggestion.brightness,
      'contrast': suggestion.contrast,
      'saturation': suggestion.saturation,
    });
    if (selected != clipId) selectClip(selected);
    return true;
  }

  /// Cuts the subject out of image clip [clipId] and swaps the clip's
  /// picture for the cutout, a PNG kept next to the project's media. The
  /// original file stays where it was, and undo brings it back. Returns
  /// false when the clip is not an image or the engine failed.
  Future<bool> removeBackground(String clipId) async {
    final clip = state.valueOrNull?.project.clipById(clipId);
    if (clip == null || clip.kind != MediaKind.image || clip.text != null) {
      return false;
    }
    final library = await ref.read(mediaLibraryProvider.future);
    final dir =
        Directory('${library.root.path}${Platform.pathSeparator}cutouts');
    final out = '${dir.path}${Platform.pathSeparator}'
        '${DateTime.now().microsecondsSinceEpoch}.png';
    final ({int width, int height}) size;
    try {
      await dir.create(recursive: true);
      size = await ref
          .read(mediaEngineProvider)
          .removeBackground(filePathOf(clip.sourceUri), out);
    } on Object {
      return false;
    }
    return _run(
      'remove background',
      (project) => ref.read(replaceClipPictureProvider).call(
            projectId: project.id,
            clipId: clipId,
            sourceUri: out,
            width: size.width,
            height: size.height,
          ),
    );
  }

  /// Renders [drawing] to a PNG in the media library, sized to the project's
  /// canvas (at most [_drawingMaxSide] px on its long side).
  Future<({String path, int width, int height})> _renderDrawing(
    Project project,
    ClipDrawing drawing,
  ) async {
    final canvas = project.canvas;
    final shrink = (_drawingMaxSide /
            (canvas.width > canvas.height ? canvas.width : canvas.height))
        .clamp(0.0, 1.0);
    final width = (canvas.width * shrink).round();
    final height = (canvas.height * shrink).round();
    final png = await renderDrawingPng(drawing, width, height);
    final library = await ref.read(mediaLibraryProvider.future);
    final dir =
        Directory('${library.root.path}${Platform.pathSeparator}drawings');
    await dir.create(recursive: true);
    final path = '${dir.path}${Platform.pathSeparator}'
        '${DateTime.now().microsecondsSinceEpoch}.png';
    await File(path).writeAsBytes(png, flush: true);
    return (path: path, width: width, height: height);
  }

  /// Adds [drawing] over the video at [startMs], selects it and returns its
  /// id; null when it was blank or the picture could not be made.
  Future<String?> addDrawing(ClipDrawing drawing, int startMs) async {
    final before = state.valueOrNull?.project;
    if (before == null || drawing.isBlank) return null;
    final ({String path, int width, int height}) picture;
    try {
      picture = await _renderDrawing(before, drawing);
    } on Object {
      return null;
    }
    final ok = await _run(
      'drawing',
      (project) => ref.read(addDrawingClipProvider).call(
            projectId: project.id,
            drawing: drawing,
            sourceUri: picture.path,
            width: picture.width,
            height: picture.height,
            startMs: startMs,
          ),
    );
    if (!ok) return null;
    final added = _newClipIds(before, state.requireValue.project);
    if (added.isEmpty) return null;
    selectClip(added.first);
    return added.first;
  }

  /// Saves new strokes for drawing clip [clipId]; false when it is not a
  /// drawing, the drawing is blank or the picture could not be made.
  Future<bool> setDrawing(String clipId, ClipDrawing drawing) async {
    final project = state.valueOrNull?.project;
    if (project == null || drawing.isBlank) return false;
    final ({String path, int width, int height}) picture;
    try {
      picture = await _renderDrawing(project, drawing);
    } on Object {
      return false;
    }
    return _run(
      'drawing',
      (project) => ref.read(setClipDrawingProvider).call(
            projectId: project.id,
            clipId: clipId,
            drawing: drawing,
            sourceUri: picture.path,
            width: picture.width,
            height: picture.height,
          ),
    );
  }

  /// Changes the frame the project renders to.
  Future<void> setCanvas(Canvas canvas) async {
    await _run(
      'canvas',
      (project) => ref
          .read(setCanvasProvider)
          .call(projectId: project.id, canvas: canvas),
    );
  }

  /// Saves where and how the picture of clip [clipId] sits on the canvas.
  Future<void> setTransform(String clipId, ClipTransform transform) async {
    await _run(
      'transform',
      (project) => ref.read(setClipTransformProvider).call(
            projectId: project.id,
            clipId: clipId,
            transform: transform,
          ),
    );
  }

  /// Adds [text] over the video at [startMs], selects it and returns its
  /// id; null when the edit was rejected.
  Future<String?> addText(ClipText text, int startMs) async {
    final before = state.valueOrNull?.project;
    if (before == null) return null;
    final size = _measure(text);
    final ok = await _run(
      'text',
      (project) => ref.read(addTextClipProvider).call(
            projectId: project.id,
            text: text,
            width: size.width,
            height: size.height,
            startMs: startMs,
          ),
    );
    if (!ok) return null;
    final added = _newClipIds(before, state.requireValue.project);
    if (added.isEmpty) return null;
    selectClip(added.first);
    _lastTextEdit = null;
    return added.first;
  }

  /// Saves the words and look of text clip [clipId]. Edits of one text in
  /// quick succession (typing, dragging a slider) are one step of undo.
  Future<void> setText(String clipId, ClipText text) async {
    final size = _measure(text);
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastTextEdit;
    final continuing =
        last != null && last.clipId == clipId && now - last.atMs < _textBurstMs;
    await _run(
      'text',
      (project) => ref.read(setClipTextProvider).call(
            projectId: project.id,
            clipId: clipId,
            text: text,
            width: size.width,
            height: size.height,
          ),
      remember: !continuing,
    );
    _lastTextEdit = (clipId: clipId, atMs: now);
  }

  TextSize _measure(ClipText text) => ref
      .read(mediaEngineProvider)
      .measureText(engineTextOf(text), textReferenceHeight);

  /// Deletes the open project for good, with its versions, and forgets its
  /// own settings. Exported videos stay. Returns whether it was deleted; the
  /// caller asks the user first and leaves the editor.
  Future<bool> deleteProject() async {
    final current = state.valueOrNull;
    if (current == null) return false;
    final id = current.project.id;
    // No more automatic restore points for a project that is going away.
    _labels = null;
    await ref.read(projectRepositoryProvider).delete(id);
    await ref.read(settingsStoreProvider).write(projectExportDirKey(id), '');
    ref
      ..invalidate(projectSummariesProvider)
      ..invalidate(projectExportDirProvider(id));
    return true;
  }

  /// Puts the layers in the order of [layerIds], the first being in front.
  Future<bool> reorderLayers(List<String> layerIds) => _run(
        'reorder layers',
        (project) => ref
            .read(reorderLayersProvider)
            .call(projectId: project.id, layerIds: layerIds),
      );

  /// Moves layer [layerId] [by] places (negative is toward the front).
  Future<bool> moveLayer(String layerId, int by) async {
    final project = state.valueOrNull?.project;
    if (project == null) return false;
    final ids = [for (final layer in project.layers) layer.id];
    final from = ids.indexOf(layerId);
    final to = from + by;
    if (from < 0 || to < 0 || to >= ids.length) return false;
    ids
      ..removeAt(from)
      ..insert(to, layerId);
    return reorderLayers(ids);
  }

  /// Gives the project another name; the home list shows it too.
  Future<bool> rename(String name) async {
    final ok = await _run(
      'rename',
      (project) => ref
          .read(renameProjectProvider)
          .call(projectId: project.id, name: name),
    );
    if (ok) ref.invalidate(projectSummariesProvider);
    return ok;
  }

  /// Saves the project as a named version; returns it, or null when it was
  /// rejected.
  Future<ProjectVersion?> saveVersion(String name) async {
    final current = state.valueOrNull;
    if (current == null) return null;
    final watch = Stopwatch()..start();
    final result = await ref
        .read(saveVersionProvider)
        .call(projectId: current.project.id, name: name);
    ref
        .read(editLogProvider)
        .record('save version', watch.elapsedMilliseconds, result);
    ref.invalidate(projectVersionsProvider(current.project.id));
    switch (result) {
      case Ok<ProjectVersion>(:final value):
        _lastCheckpointMs = value.createdAtMs;
        return value;
      case Err<ProjectVersion>(:final failure):
        state = AsyncValue.data(
          (state.valueOrNull ?? current).copyWith(failure: () => failure),
        );
        return null;
    }
  }

  /// Puts the project back to version [versionId]. The state it replaces is
  /// first saved as a restore point of its own, so it can be brought back
  /// even after the editor closes; within the session undo does it too.
  Future<void> restoreVersion(String versionId) async {
    final labels = _labels;
    if (labels != null) {
      final versions = await ref
          .read(versionRepositoryProvider)
          .versionsOf(state.valueOrNull?.project.id ?? '');
      final target = versions.where((v) => v.id == versionId);
      if (target.isNotEmpty) {
        await _checkpoint(labels.beforeRestore(target.first.name));
      }
    }
    final ok = await _run(
      'restore version',
      (project) => ref
          .read(restoreVersionProvider)
          .call(projectId: project.id, versionId: versionId),
    );
    if (ok) selectClip(null);
  }

  /// Goes back one edit.
  Future<void> undo() => _travel(_history.undo);

  /// Goes forward one undone edit.
  Future<void> redo() => _travel(_history.redo);

  Future<void> _travel(Project? Function(Project current) step) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final target = step(current.project);
    if (target == null) return;
    await ref.read(restoreProjectProvider).call(target);
    final selected = current.selectedClipId;
    state = AsyncValue.data(
      current.copyWith(
        project: target,
        selectedClipId: () =>
            selected != null && target.clipById(selected) != null
                ? selected
                : null,
        failure: () => null,
        canUndo: _history.canUndo,
        canRedo: _history.canRedo,
      ),
    );
  }

  static CanvasPreset _closestPreset(double aspect) {
    var best = CanvasPreset.portrait;
    var distance = double.infinity;
    for (final preset in CanvasPreset.values) {
      final d = (preset.width / preset.height - aspect).abs();
      if (d < distance) {
        distance = d;
        best = preset;
      }
    }
    return best;
  }

  /// The back-most layer holding pictures: the main sequence.
  static bool _isMainLayer(Project project, Layer layer) {
    if (layer.kind == MediaKind.audio || layer.kind == MediaKind.text) {
      return false;
    }
    final visual = project.layers
        .where((l) => l.kind != MediaKind.audio && l.kind != MediaKind.text)
        .toList();
    return visual.isNotEmpty && visual.last.id == layer.id;
  }

  static List<String> _newClipIds(Project before, Project after) {
    final old = {
      for (final layer in before.layers)
        for (final clip in layer.clips) clip.id,
    };
    return [
      for (final layer in after.layers)
        for (final clip in layer.clips)
          if (!old.contains(clip.id)) clip.id,
    ];
  }

  /// Layers exist for what is on them: once an edit leaves one without
  /// clips it is removed and the result stored, so a project never shows
  /// stray empty layers. A project with no clip at all keeps its layers (a
  /// template waiting for media).
  Future<Project> _dropEmptyLayers(Project project) async {
    final hasClips = project.layers.any((layer) => layer.clips.isNotEmpty);
    if (!hasClips) return project;
    final tidy = project.withoutEmptyLayers();
    if (identical(tidy, project)) return project;
    await ref.read(projectRepositoryProvider).save(tidy);
    return tidy;
  }

  /// Applies one use case: Ok replaces the project and records the previous
  /// one for undo, Err records the failure and leaves the project unchanged.
  /// Returns whether the edit was accepted.
  Future<bool> _run(
    String label,
    Future<EditorResult<Project>> Function(Project project) action, {
    bool remember = true,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    final watch = Stopwatch()..start();
    final result = await action(current.project);
    final latest = state.valueOrNull ?? current;
    ref.read(editLogProvider).record(label, watch.elapsedMilliseconds, result);
    switch (result) {
      case Ok<Project>(:final value):
        if (remember) _history.record(latest.project);
        final tidy = await _dropEmptyLayers(value);
        state = AsyncValue.data(
          latest.copyWith(
            project: tidy,
            failure: () => null,
            canUndo: _history.canUndo,
            canRedo: _history.canRedo,
          ),
        );
        _checkpointIfDue();
        return true;
      case Err<Project>(:final failure):
        state = AsyncValue.data(latest.copyWith(failure: () => failure));
        return false;
    }
  }
}
