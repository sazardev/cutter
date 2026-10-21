import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';

/// Whether a file can stand in for the missing source of some clips.
enum RelinkCheck {
  /// The file fits every clip that used the missing source.
  ok,

  /// No clip uses the missing source.
  notUsed,

  /// The file is another kind of media than the clips expect.
  wrongKind,

  /// The file is shorter than a clip needs, so the clip would run past its
  /// end.
  tooShort,

  /// The file cannot be read.
  unreadable,
}

/// Checks whether [asset] can replace the source [oldUri] in [project].
RelinkCheck relinkCheck(Project project, String oldUri, MediaAsset asset) {
  if (!asset.supported) return RelinkCheck.unreadable;
  var used = false;
  for (final layer in project.layers) {
    for (final clip in layer.clips) {
      if (clip.sourceUri != oldUri) continue;
      used = true;
      if (clip.kind != asset.kind) return RelinkCheck.wrongKind;
      if (asset.kind != MediaKind.image && asset.durationMs < clip.outPointMs) {
        return RelinkCheck.tooShort;
      }
    }
  }
  return used ? RelinkCheck.ok : RelinkCheck.notUsed;
}

/// Points every clip that used a missing file at another file, keeping each
/// clip's place and trim.
class RelinkMedia {
  /// Creates the use case over [_projects].
  RelinkMedia(this._projects);

  final ProjectRepository _projects;

  /// Replaces the source [oldUri] by [asset] in project [projectId].
  Future<EditorResult<Project>> call({
    required String projectId,
    required String oldUri,
    required MediaAsset asset,
  }) async {
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    if (relinkCheck(project, oldUri, asset) != RelinkCheck.ok) {
      return const Err(UnsupportedMedia());
    }
    final updated = project.withLayers([
      for (final layer in project.layers)
        layer.withClips([
          for (final clip in layer.clips)
            if (clip.sourceUri == oldUri)
              clip.copyWith(
                sourceUri: asset.uri,
                assetId: asset.id,
                sourceWidth: asset.width > 0 ? asset.width : null,
                sourceHeight: asset.height > 0 ? asset.height : null,
              )
            else
              clip,
        ]),
    ]);
    await _projects.save(updated);
    return Ok(updated);
  }
}
