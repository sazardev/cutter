import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/clip_crop.dart';
import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';

/// Loads clip [clipId], applies [change] and saves, rejecting a result that
/// overlaps another clip of its layer.
Future<EditorResult<Project>> _change(
  ProjectRepository projects,
  String projectId,
  String clipId,
  EditorResult<Clip> Function(Clip clip) change,
) async {
  final project = await projects.find(projectId);
  if (project == null) return Err(ProjectNotFound(projectId));
  final clip = project.clipById(clipId);
  final layer = project.layerOfClip(clipId);
  if (clip == null || layer == null) return Err(ClipNotFound(clipId));
  switch (change(clip)) {
    case Err<Clip>(:final failure):
      return Err(failure);
    case Ok<Clip>(:final value):
      for (final other in layer.clips) {
        if (other.id != clipId && other.range.overlaps(value.range)) {
          return Err(Overlap(other.id));
        }
      }
      final updated = project.replaceLayer(_replace(layer, value));
      await projects.save(updated);
      return Ok(updated);
  }
}

Layer _replace(Layer layer, Clip clip) => layer.withClips([
      for (final other in layer.clips)
        if (other.id == clip.id) clip else other,
    ]);

/// Plays a clip faster or slower. The clip keeps its start and its source
/// range, so it gets shorter or longer on the timeline; a speed that would
/// run into the next clip is rejected.
class SetClipSpeed {
  /// Creates the use case over [_projects].
  SetClipSpeed(this._projects);

  final ProjectRepository _projects;

  /// Sets clip [clipId] of project [projectId] to [speed].
  Future<EditorResult<Project>> call({
    required String projectId,
    required String clipId,
    required double speed,
  }) {
    return _change(_projects, projectId, clipId, (clip) {
      if (clip.kind == MediaKind.image) return const Err(IncompatibleClip());
      if (speed < minClipSpeed || speed > maxClipSpeed) {
        return const Err(InvalidSpeed());
      }
      final changed = clip.copyWith(speed: speed);
      if (changed.durationMs < minClipDurationMs) {
        return const Err(ZeroDuration());
      }
      // Fades cannot outlast the shorter clip.
      final half = changed.durationMs ~/ 2;
      return Ok(
        changed.copyWith(
          fadeInMs: clip.fadeInMs.clamp(0, half),
          fadeOutMs: clip.fadeOutMs.clamp(0, half),
        ),
      );
    });
  }
}

/// Fades the sound of a clip in at its start and out at its end.
class SetClipFades {
  /// Creates the use case over [_projects].
  SetClipFades(this._projects);

  final ProjectRepository _projects;

  /// Gives clip [clipId] fades of [inMs] and [outMs], each at most half of
  /// the clip.
  Future<EditorResult<Project>> call({
    required String projectId,
    required String clipId,
    required int inMs,
    required int outMs,
  }) {
    return _change(_projects, projectId, clipId, (clip) {
      if (clip.kind == MediaKind.image) return const Err(IncompatibleClip());
      final half = clip.durationMs ~/ 2;
      if (inMs < 0 || outMs < 0 || inMs > half || outMs > half) {
        return const Err(InvalidFade());
      }
      return Ok(clip.copyWith(fadeInMs: inMs, fadeOutMs: outMs));
    });
  }
}

/// Keeps only part of the picture of a clip.
class SetClipCrop {
  /// Creates the use case over [_projects].
  SetClipCrop(this._projects);

  final ProjectRepository _projects;

  /// Gives clip [clipId] the [crop].
  Future<EditorResult<Project>> call({
    required String projectId,
    required String clipId,
    required ClipCrop crop,
  }) {
    return _change(_projects, projectId, clipId, (clip) {
      if (clip.kind == MediaKind.audio) return const Err(IncompatibleClip());
      if (!crop.isValid) return const Err(InvalidCrop());
      return Ok(clip.copyWith(crop: crop));
    });
  }
}

/// Sets how long a still image shows, keeping its start.
class SetImageDuration {
  /// Creates the use case over [_projects].
  SetImageDuration(this._projects);

  final ProjectRepository _projects;

  /// Makes image clip [clipId] last [durationMs].
  Future<EditorResult<Project>> call({
    required String projectId,
    required String clipId,
    required int durationMs,
  }) {
    return _change(_projects, projectId, clipId, (clip) {
      if (clip.kind != MediaKind.image) return const Err(IncompatibleClip());
      if (durationMs < minClipDurationMs ||
          clip.inPointMs + durationMs > clip.sourceDurationMs) {
        return const Err(ZeroDuration());
      }
      return Ok(clip.copyWith(outPointMs: clip.inPointMs + durationMs));
    });
  }
}
