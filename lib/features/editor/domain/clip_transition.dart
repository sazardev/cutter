import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';

/// The ways to get from one clip to the next, each a pair of the clip
/// animations: the first clip leaves one way and the second comes in the
/// matching way.
enum TransitionKind {
  /// The first clip fades out and the second fades in.
  dip('fade', 'fade'),

  /// The first clip slides out to the left, the second slides in from the
  /// right.
  pushLeft('slide_left', 'slide_right'),

  /// The first slides out to the right, the second in from the left.
  pushRight('slide_right', 'slide_left'),

  /// The first slides out upwards, the second in from below.
  pushUp('slide_up', 'slide_down'),

  /// The first slides out downwards, the second in from above.
  pushDown('slide_down', 'slide_up'),

  /// The first grows past the camera as it fades, the second grows into
  /// place.
  zoomThrough('zoom_out', 'zoom_in'),

  /// Both turn: the first spins away, the second spins in.
  spin('spin', 'spin'),

  /// The first fades out, the second pops in.
  pop('fade', 'pop');

  const TransitionKind(this.animOut, this.animIn);

  /// Animation the first clip leaves with.
  final String animOut;

  /// Animation the second clip comes in with.
  final String animIn;
}

/// Shortest and longest a transition may last, per side, in milliseconds.
const int minTransitionMs = 200;

/// Longest a transition may last, per side.
const int maxTransitionMs = 2000;

/// How much empty time may sit between two clips for them to count as
/// neighbours.
const int maxTransitionGapMs = 250;

/// The clip right before [clip] on its layer, or null when it starts the
/// layer or there is a gap longer than [maxTransitionGapMs] before it.
Clip? previousNeighbour(Layer layer, Clip clip) {
  Clip? best;
  for (final other in layer.clips) {
    if (other.id == clip.id || other.range.endMs > clip.startMs) continue;
    if (best == null || other.range.endMs > best.range.endMs) best = other;
  }
  if (best == null) return null;
  return clip.startMs - best.range.endMs <= maxTransitionGapMs ? best : null;
}

/// The transition that joins [first] to [second], or null when they are not
/// joined by one of the [TransitionKind]s.
TransitionKind? transitionBetween(Clip first, Clip second) {
  for (final kind in TransitionKind.values) {
    if (first.animOut == kind.animOut && second.animIn == kind.animIn) {
      return kind;
    }
  }
  return null;
}

/// Joins a clip to the one before it with a transition: the first clip's
/// exit and this clip's entrance are set to the pair, and the sound of both
/// is faded the same length when asked.
class ApplyTransition {
  /// Creates the use case over [_projects].
  const ApplyTransition(this._projects);

  final ProjectRepository _projects;

  /// Puts [kind], [durationMs] long on each side, between [clipId] and the
  /// clip before it. The length is cut to what each clip can hold.
  Future<EditorResult<Project>> call({
    required String projectId,
    required String clipId,
    required TransitionKind kind,
    required int durationMs,
    bool fadeSound = true,
  }) async {
    if (durationMs < minTransitionMs || durationMs > maxTransitionMs) {
      return const Err(InvalidAnimation());
    }
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    final second = project.clipById(clipId);
    final layer = project.layerOfClip(clipId);
    if (second == null || layer == null) return Err(ClipNotFound(clipId));
    final first = previousNeighbour(layer, second);
    if (first == null || !_canJoin(first) || !_canJoin(second)) {
      return const Err(IncompatibleClip());
    }

    final updated = project.replaceLayer(
      layer.withClips([
        for (final clip in layer.clips)
          if (clip.id == first.id)
            _leaving(clip, kind, durationMs, fadeSound)
          else if (clip.id == second.id)
            _arriving(clip, kind, durationMs, fadeSound)
          else
            clip,
      ]),
    );
    await _projects.save(updated);
    return Ok(updated);
  }

  // A title has its own animation.
  bool _canJoin(Clip clip) => clip.text == null;

  int _fit(Clip clip, int ms) => ms.clamp(0, clip.durationMs ~/ 2);

  Clip _leaving(Clip clip, TransitionKind kind, int ms, bool fadeSound) {
    final length = _fit(clip, ms);
    return clip.copyWith(
      animOut: clip.kind == MediaKind.audio ? null : kind.animOut,
      clearAnimOut: clip.kind == MediaKind.audio,
      animOutMs: clip.kind == MediaKind.audio ? 0 : length,
      fadeOutMs:
          fadeSound && clip.kind != MediaKind.image ? length : clip.fadeOutMs,
    );
  }

  Clip _arriving(Clip clip, TransitionKind kind, int ms, bool fadeSound) {
    final length = _fit(clip, ms);
    return clip.copyWith(
      animIn: clip.kind == MediaKind.audio ? null : kind.animIn,
      clearAnimIn: clip.kind == MediaKind.audio,
      animInMs: clip.kind == MediaKind.audio ? 0 : length,
      fadeInMs:
          fadeSound && clip.kind != MediaKind.image ? length : clip.fadeInMs,
    );
  }
}

/// Takes the transition off the join between a clip and the one before it:
/// the exit, the entrance and the sound fades of the join are cleared.
class RemoveTransition {
  /// Creates the use case over [_projects].
  const RemoveTransition(this._projects);

  final ProjectRepository _projects;

  /// Clears the join of [clipId] with its previous neighbour.
  Future<EditorResult<Project>> call({
    required String projectId,
    required String clipId,
  }) async {
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    final second = project.clipById(clipId);
    final layer = project.layerOfClip(clipId);
    if (second == null || layer == null) return Err(ClipNotFound(clipId));
    final first = previousNeighbour(layer, second);
    if (first == null) return const Err(IncompatibleClip());
    final updated = project.replaceLayer(
      layer.withClips([
        for (final clip in layer.clips)
          if (clip.id == first.id)
            clip.copyWith(clearAnimOut: true, animOutMs: 0, fadeOutMs: 0)
          else if (clip.id == second.id)
            clip.copyWith(clearAnimIn: true, animInMs: 0, fadeInMs: 0)
          else
            clip,
      ]),
    );
    await _projects.save(updated);
    return Ok(updated);
  }
}
