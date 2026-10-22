import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/clip_text.dart';
import 'package:cutter/features/editor/domain/clip_transform.dart';
import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/domain/time_range.dart';

/// How far down each text that starts over another one is nudged, as a
/// fraction of the canvas height, so stacked texts do not hide each other.
const _stackStep = 0.12;

/// Most texts nudged this way before the next one is centred again.
const _stackDepth = 4;

/// Adds a text at its start time on the first text layer where it fits, or on a
/// new text layer in front of everything: texts that share time end up on
/// layers of their own, one after the other in time on the same layer.
class AddTextClip {
  /// Creates the use case over the given project storage and id source.
  AddTextClip(this._projects, this._ids);

  final ProjectRepository _projects;
  final IdGenerator _ids;

  /// Adds [text], framed by a picture of [width]x[height] reference pixels
  /// (see `measureText`), to project [projectId].
  Future<EditorResult<Project>> call({
    required String projectId,
    required ClipText text,
    required int width,
    required int height,
    required int startMs,
    int durationMs = defaultTextDurationMs,
  }) async {
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    if (!text.isValid) return const Err(InvalidText());
    if (startMs < 0) return const Err(NegativeStart());

    final range = TimeRange(startMs, durationMs);
    var sharing = 0;
    Layer? target;
    for (final layer in project.layers) {
      if (layer.kind != MediaKind.text) continue;
      final busy = layer.clips.where((c) => c.range.overlaps(range)).length;
      sharing += busy;
      if (busy == 0 && target == null) target = layer;
    }

    final layer =
        target ?? Layer(id: _ids.next(), name: '', kind: MediaKind.text);
    final clip = Clip(
      id: _ids.next(),
      layerId: layer.id,
      assetId: '',
      sourceUri: '',
      kind: MediaKind.text,
      startMs: startMs,
      inPointMs: textSourceSpanMs,
      outPointMs: textSourceSpanMs + durationMs,
      sourceDurationMs: 2 * textSourceSpanMs,
      sourceWidth: width,
      sourceHeight: height,
      transform: ClipTransform(
        y: sharing == 0 ? 0 : (sharing % _stackDepth) * _stackStep,
      ),
      text: text,
    );
    final withClip = layer.withClips([...layer.clips, clip]);
    final updated = target == null
        ? project.withLayers([withClip, ...project.layers])
        : project.replaceLayer(withClip);
    await _projects.save(updated);
    return Ok(updated);
  }
}

/// Changes the words or the look of a text clip.
class SetClipText {
  /// Creates the use case over [_projects].
  SetClipText(this._projects);

  final ProjectRepository _projects;

  /// Gives clip [clipId] the [text], framed by a picture of [width]x[height]
  /// reference pixels.
  Future<EditorResult<Project>> call({
    required String projectId,
    required String clipId,
    required ClipText text,
    required int width,
    required int height,
  }) async {
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    final clip = project.clipById(clipId);
    final layer = project.layerOfClip(clipId);
    if (clip == null || layer == null) return Err(ClipNotFound(clipId));
    if (clip.kind != MediaKind.text || !text.isValid) {
      return const Err(InvalidText());
    }

    final changed = clip.copyWith(
      text: text,
      sourceWidth: width,
      sourceHeight: height,
    );
    final updated = project.replaceLayer(
      layer.withClips([
        for (final other in layer.clips)
          if (other.id == clipId) changed else other,
      ]),
    );
    await _projects.save(updated);
    return Ok(updated);
  }
}
