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

/// Where on a clip a transition goes.
enum TransitionEdge {
  /// Where the clip begins: it joins the clip before it, or fades in alone.
  start,

  /// Where the clip ends: it joins the clip after it, or leaves alone.
  end,

  /// Both ends.
  both,
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

/// The clip right after [clip] on its layer, or null when it ends the layer
/// or there is a gap longer than [maxTransitionGapMs] after it.
Clip? nextNeighbour(Layer layer, Clip clip) {
  Clip? best;
  for (final other in layer.clips) {
    if (other.id == clip.id || other.startMs < clip.range.endMs) continue;
    if (best == null || other.startMs < best.startMs) best = other;
  }
  if (best == null) return null;
  return best.startMs - clip.range.endMs <= maxTransitionGapMs ? best : null;
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

/// Puts a transition on a clip: at its start, at its end or at both. Where a
/// neighbour touches that end, the join is made of both clips (the first
/// leaves, the second comes in) and the sound of both is faded the same
/// length when asked; with no neighbour the clip fades or moves alone.
class ApplyTransition {
  /// Creates the use case over [_projects].
  const ApplyTransition(this._projects);

  final ProjectRepository _projects;

  /// Puts [kind], [durationMs] long on each side, at [edge] of [clipId]. The
  /// length is cut to what each clip can hold.
  Future<EditorResult<Project>> call({
    required String projectId,
    required String clipId,
    required TransitionKind kind,
    required int durationMs,
    bool fadeSound = true,
    TransitionEdge edge = TransitionEdge.start,
  }) async {
    if (durationMs < minTransitionMs || durationMs > maxTransitionMs) {
      return const Err(InvalidAnimation());
    }
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    final target = project.clipById(clipId);
    final layer = project.layerOfClip(clipId);
    if (target == null || layer == null) return Err(ClipNotFound(clipId));
    if (!_canJoin(target)) return const Err(IncompatibleClip());

    final entering = edge != TransitionEdge.end;
    final leaving = edge != TransitionEdge.start;
    final before = entering ? previousNeighbour(layer, target) : null;
    final after = leaving ? nextNeighbour(layer, target) : null;

    final updated = project.replaceLayer(
      layer.withClips([
        for (final clip in layer.clips)
          if (clip.id == target.id)
            _both(
              clip,
              kind,
              durationMs,
              fadeSound,
              entering: entering,
              leaving: leaving,
            )
          else if (clip.id == before?.id && _canJoin(clip))
            _leaving(clip, kind, durationMs, fadeSound)
          else if (clip.id == after?.id && _canJoin(clip))
            _arriving(clip, kind, durationMs, fadeSound)
          else
            clip,
      ]),
    );
    await _projects.save(updated);
    return Ok(updated);
  }

  Clip _both(
    Clip clip,
    TransitionKind kind,
    int ms,
    bool fadeSound, {
    required bool entering,
    required bool leaving,
  }) {
    var result = clip;
    if (entering) result = _arriving(result, kind, ms, fadeSound);
    if (leaving) result = _leaving(result, kind, ms, fadeSound);
    return result;
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

/// Takes the transition off a clip: the exit, the entrance and the sound
/// fades of the chosen edge are cleared, and so are those of the neighbour
/// that shared the join.
class RemoveTransition {
  /// Creates the use case over [_projects].
  const RemoveTransition(this._projects);

  final ProjectRepository _projects;

  /// Clears [edge] of [clipId] and the neighbour across it.
  Future<EditorResult<Project>> call({
    required String projectId,
    required String clipId,
    TransitionEdge edge = TransitionEdge.start,
  }) async {
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    final target = project.clipById(clipId);
    final layer = project.layerOfClip(clipId);
    if (target == null || layer == null) return Err(ClipNotFound(clipId));
    final clearIn = edge != TransitionEdge.end;
    final clearOut = edge != TransitionEdge.start;
    final before = clearIn ? previousNeighbour(layer, target) : null;
    final after = clearOut ? nextNeighbour(layer, target) : null;
    Clip cleared(Clip clip, {required bool inSide, required bool outSide}) =>
        clip.copyWith(
          clearAnimIn: inSide,
          animInMs: inSide ? 0 : null,
          fadeInMs: inSide ? 0 : null,
          clearAnimOut: outSide,
          animOutMs: outSide ? 0 : null,
          fadeOutMs: outSide ? 0 : null,
        );
    final updated = project.replaceLayer(
      layer.withClips([
        for (final clip in layer.clips)
          if (clip.id == target.id)
            cleared(clip, inSide: clearIn, outSide: clearOut)
          else if (clip.id == before?.id)
            cleared(clip, inSide: false, outSide: true)
          else if (clip.id == after?.id)
            cleared(clip, inSide: true, outSide: false)
          else
            clip,
      ]),
    );
    await _projects.save(updated);
    return Ok(updated);
  }
}
