import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Everything the editor screen shows: the project, the playhead, the
/// selected clip and the failure of the last rejected action.
class EditorUiState {
  /// Creates the editor state for [project].
  const EditorUiState({
    required this.project,
    this.playheadMs = 0,
    this.selectedClipId,
    this.failure,
  });

  /// The project being edited.
  final Project project;

  /// The playhead position in milliseconds.
  final int playheadMs;

  /// The id of the selected clip, or null when nothing is selected.
  final String? selectedClipId;

  /// The failure of the last rejected action, or null when there is none.
  final EditorFailure? failure;

  /// Returns a copy with the given fields replaced; nullable fields are set
  /// through a callback so that null can be assigned explicitly.
  EditorUiState copyWith({
    Project? project,
    int? playheadMs,
    String? Function()? selectedClipId,
    EditorFailure? Function()? failure,
  }) {
    return EditorUiState(
      project: project ?? this.project,
      playheadMs: playheadMs ?? this.playheadMs,
      selectedClipId:
          selectedClipId != null ? selectedClipId() : this.selectedClipId,
      failure: failure != null ? failure() : this.failure,
    );
  }
}

/// Runs the domain use cases against the playhead and the selected clip.
class EditorController extends Notifier<AsyncValue<EditorUiState>> {
  @override
  AsyncValue<EditorUiState> build() => const AsyncValue.loading();

  /// Loads the project with [projectId] from the local database.
  Future<void> load(String projectId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final project = await ref.read(projectRepositoryProvider).find(projectId);
      if (project == null) {
        throw StateError('Project $projectId was not found.');
      }
      return EditorUiState(project: project);
    });
  }

  /// Moves the playhead, never before zero.
  void seek(int ms) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(
      current.copyWith(playheadMs: ms < 0 ? 0 : ms),
    );
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

  /// True only when a clip is selected and the playhead is strictly inside it.
  bool get canSplit {
    final current = state.valueOrNull;
    final clip = _selectedClip(current);
    if (current == null || clip == null) return false;
    final end = clip.startMs + clip.durationMs;
    return clip.startMs < current.playheadMs && current.playheadMs < end;
  }

  /// Splits the selected clip at the playhead.
  Future<void> splitAtPlayhead() async {
    final current = state.valueOrNull;
    final clip = _selectedClip(current);
    if (current == null || clip == null) return;
    await _run(
      (project) => ref.read(splitClipProvider).call(
            projectId: project.id,
            clipId: clip.id,
            atMs: current.playheadMs,
          ),
    );
  }

  /// Moves the selected clip by [deltaMs] on its layer, never before zero.
  Future<void> nudgeSelected(int deltaMs) async {
    final current = state.valueOrNull;
    final clip = _selectedClip(current);
    if (current == null || clip == null) return;
    final layer = current.project.layers.firstWhere(
      (layer) => layer.clips.any((candidate) => candidate.id == clip.id),
    );
    final newStart = clip.startMs + deltaMs;
    await _run(
      (project) => ref.read(moveClipProvider).call(
            projectId: project.id,
            clipId: clip.id,
            targetLayerId: layer.id,
            startMs: newStart < 0 ? 0 : newStart,
          ),
    );
  }

  /// Flips the reverse flag of the selected clip.
  Future<void> toggleReverse() async {
    final clip = _selectedClip(state.valueOrNull);
    if (clip == null) return;
    await _run(
      (project) => ref.read(setClipReverseProvider).call(
            projectId: project.id,
            clipId: clip.id,
            enabled: !clip.reversed,
          ),
    );
  }

  /// Trims the selected clip to [inPointMs]..[outPointMs] of its source.
  Future<void> trimSelectedClip({
    required int inPointMs,
    required int outPointMs,
  }) async {
    final clip = _selectedClip(state.valueOrNull);
    if (clip == null) return;
    await _run(
      (project) => ref.read(trimClipProvider).call(
            projectId: project.id,
            clipId: clip.id,
            inPointMs: inPointMs,
            outPointMs: outPointMs,
          ),
    );
  }

  /// Sets the volume of the selected clip.
  Future<void> setClipVolume(double value) async {
    final clip = _selectedClip(state.valueOrNull);
    if (clip == null) return;
    await _run(
      (project) => ref.read(setClipVolumeProvider).call(
            projectId: project.id,
            clipId: clip.id,
            volume: value,
          ),
    );
  }

  /// Sets the filter of the selected clip; null removes it.
  Future<void> setFilter(String? filterId) async {
    final clip = _selectedClip(state.valueOrNull);
    if (clip == null) return;
    await _run(
      (project) => ref.read(setClipFilterProvider).call(
            projectId: project.id,
            clipId: clip.id,
            filterId: filterId,
          ),
    );
  }

  /// Sets one adjustment [key] of the selected clip to [value], keeping the
  /// other adjustments of the clip.
  Future<void> setAdjustment(String key, double value) async {
    final clip = _selectedClip(state.valueOrNull);
    if (clip == null) return;
    final adjustments = Map<String, double>.of(clip.adjustments)..[key] = value;
    await _run(
      (project) => ref.read(setClipAdjustmentsProvider).call(
            projectId: project.id,
            clipId: clip.id,
            adjustments: adjustments,
          ),
    );
  }

  Clip? _selectedClip(EditorUiState? current) {
    final id = current?.selectedClipId;
    if (current == null || id == null) return null;
    for (final layer in current.project.layers) {
      for (final clip in layer.clips) {
        if (clip.id == id) return clip;
      }
    }
    return null;
  }

  /// Applies one use case: Ok replaces the project, Err records the failure
  /// and leaves the project unchanged.
  Future<void> _run(
    Future<EditorResult<Project>> Function(Project project) action,
  ) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final result = await action(current.project);
    final latest = state.valueOrNull ?? current;
    switch (result) {
      case Ok<Project>(:final value):
        state = AsyncValue.data(
          latest.copyWith(project: value, failure: () => null),
        );
      case Err<Project>(:final failure):
        state = AsyncValue.data(latest.copyWith(failure: () => failure));
    }
  }
}
