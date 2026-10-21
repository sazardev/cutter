import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';

/// The adjustment keys the editor supports.
const adjustmentKeys = {'brightness', 'contrast', 'saturation'};

/// Lowest value an adjustment may take.
const adjustmentMin = -1.0;

/// Highest value an adjustment may take.
const adjustmentMax = 1.0;

const _minVolume = 0.0;
const _maxVolume = 1.0;

/// Loads the project and clip, applies [change] to the clip and saves the
/// result. Nothing is saved when [change] or a lookup fails.
Future<EditorResult<Project>> _updateClip(
  ProjectRepository repository, {
  required String projectId,
  required String clipId,
  required EditorResult<Clip> Function(Clip clip) change,
}) async {
  final project = await repository.find(projectId);
  if (project == null) return Err(ProjectNotFound(projectId));
  final clip = project.clipById(clipId);
  final layer = project.layerOfClip(clipId);
  if (clip == null || layer == null) return Err(ClipNotFound(clipId));

  switch (change(clip)) {
    case Err<Clip>(:final failure):
      return Err(failure);
    case Ok<Clip>(:final value):
      final updatedLayer = layer.withClips([
        for (final existing in layer.clips)
          if (existing.id == clipId) value else existing,
      ]);
      final updated = project.replaceLayer(updatedLayer);
      await repository.save(updated);
      return Ok(updated);
  }
}

bool _isValidVolume(double volume) =>
    volume >= _minVolume && volume <= _maxVolume;

/// Turns reverse playback of a video clip on or off, keeping its in and out
/// points.
class SetClipReverse {
  /// Creates the use case over [_projects].
  const SetClipReverse(this._projects);

  final ProjectRepository _projects;

  /// Sets reverse playback to [enabled] for the clip.
  Future<EditorResult<Project>> call({
    required String projectId,
    required String clipId,
    required bool enabled,
  }) {
    return _updateClip(
      _projects,
      projectId: projectId,
      clipId: clipId,
      change: (clip) {
        if (clip.kind != MediaKind.video) return const Err(NotReversible());
        return Ok(clip.copyWith(reversed: enabled));
      },
    );
  }
}

/// Sets the volume of one clip, in the range 0.0 to 1.0.
class SetClipVolume {
  /// Creates the use case over [_projects].
  const SetClipVolume(this._projects);

  final ProjectRepository _projects;

  /// Sets the clip volume to [volume].
  Future<EditorResult<Project>> call({
    required String projectId,
    required String clipId,
    required double volume,
  }) {
    return _updateClip(
      _projects,
      projectId: projectId,
      clipId: clipId,
      change: (clip) {
        if (!_isValidVolume(volume)) return const Err(InvalidVolume());
        return Ok(clip.copyWith(volume: volume));
      },
    );
  }
}

/// Applies a filter to a video or image clip; a null filter id removes it.
class SetClipFilter {
  /// Creates the use case over [_projects].
  const SetClipFilter(this._projects);

  final ProjectRepository _projects;

  /// Applies [filterId] to the clip, or removes the filter when null.
  Future<EditorResult<Project>> call({
    required String projectId,
    required String clipId,
    String? filterId,
  }) {
    return _updateClip(
      _projects,
      projectId: projectId,
      clipId: clipId,
      change: (clip) {
        if (clip.kind == MediaKind.audio) return const Err(IncompatibleClip());
        if (filterId == null) return Ok(clip.copyWith(clearFilter: true));
        return Ok(clip.copyWith(filterId: filterId));
      },
    );
  }
}

/// Replaces the adjustments of a clip with the given map of confirmed keys.
class SetClipAdjustments {
  /// Creates the use case over [_projects].
  const SetClipAdjustments(this._projects);

  final ProjectRepository _projects;

  /// Replaces the clip adjustments with [adjustments].
  Future<EditorResult<Project>> call({
    required String projectId,
    required String clipId,
    required Map<String, double> adjustments,
  }) {
    return _updateClip(
      _projects,
      projectId: projectId,
      clipId: clipId,
      change: (clip) {
        final failure = _validateAdjustments(adjustments);
        if (failure != null) return Err(failure);
        return Ok(clip.copyWith(adjustments: Map.unmodifiable(adjustments)));
      },
    );
  }

  EditorFailure? _validateAdjustments(Map<String, double> adjustments) {
    for (final entry in adjustments.entries) {
      if (!adjustmentKeys.contains(entry.key)) {
        return UnknownAdjustment(entry.key);
      }
      final value = entry.value;
      if (value.isNaN || value < adjustmentMin || value > adjustmentMax) {
        return AdjustmentOutOfRange(entry.key);
      }
    }
    return null;
  }
}
