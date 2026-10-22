import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:flutter/foundation.dart' show immutable;

/// How a clip comes in and goes out, saved under a name so it can be applied
/// to any picture, video or title in one tap.
@immutable
class AnimationPreset {
  /// Creates a preset.
  const AnimationPreset({
    required this.id,
    required this.animIn,
    required this.animInMs,
    required this.animOut,
    required this.animOutMs,
    this.name,
  });

  /// Reads a preset from its JSON form.
  factory AnimationPreset.fromJson(Map<String, Object?> json) =>
      AnimationPreset(
        id: json['id']! as String,
        name: json['name'] as String?,
        animIn: json['animIn'] as String?,
        animInMs: json['animInMs']! as int,
        animOut: json['animOut'] as String?,
        animOutMs: json['animOutMs']! as int,
      );

  /// Unique id; built-in presets have fixed, readable ids.
  final String id;

  /// The name the user gave it; null for a built-in preset, whose name comes
  /// from the language files.
  final String? name;

  /// Id of the entrance animation, or null for none.
  final String? animIn;

  /// Length of the entrance in milliseconds.
  final int animInMs;

  /// Id of the exit animation, or null for none.
  final String? animOut;

  /// Length of the exit in milliseconds.
  final int animOutMs;

  /// Whether the preset ships with the app.
  bool get builtIn => name == null;

  /// Whether it animates neither side.
  bool get isEmpty => animIn == null && animOut == null;

  /// The JSON form of the preset.
  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'animIn': animIn,
        'animInMs': animInMs,
        'animOut': animOut,
        'animOutMs': animOutMs,
      };

  /// Whether the preset can be applied: known animation ids and lengths
  /// within the limits.
  bool get isValid {
    bool side(String? animation, int ms) =>
        ms >= 0 &&
        ms <= maxClipAnimationMs &&
        (animation == null || clipAnimationIds.contains(animation));
    return side(animIn, animInMs) && side(animOut, animOutMs);
  }

  @override
  bool operator ==(Object other) =>
      other is AnimationPreset &&
      other.id == id &&
      other.name == name &&
      other.animIn == animIn &&
      other.animInMs == animInMs &&
      other.animOut == animOut &&
      other.animOutMs == animOutMs;

  @override
  int get hashCode =>
      Object.hash(id, name, animIn, animInMs, animOut, animOutMs);
}

/// The presets that ship with the app, in the order they are listed.
const List<AnimationPreset> builtInAnimationPresets = [
  AnimationPreset(
    id: 'gentle',
    animIn: 'fade',
    animInMs: 500,
    animOut: 'fade',
    animOutMs: 500,
  ),
  AnimationPreset(
    id: 'quick_fade',
    animIn: 'fade',
    animInMs: 250,
    animOut: 'fade',
    animOutMs: 250,
  ),
  AnimationPreset(
    id: 'cinematic',
    animIn: 'fade',
    animInMs: 1200,
    animOut: 'fade',
    animOutMs: 1200,
  ),
  AnimationPreset(
    id: 'slide_through',
    animIn: 'slide_left',
    animInMs: 500,
    animOut: 'slide_right',
    animOutMs: 500,
  ),
  AnimationPreset(
    id: 'slide_up_down',
    animIn: 'slide_up',
    animInMs: 500,
    animOut: 'slide_down',
    animOutMs: 500,
  ),
  AnimationPreset(
    id: 'zoom',
    animIn: 'zoom_in',
    animInMs: 700,
    animOut: 'zoom_out',
    animOutMs: 500,
  ),
  AnimationPreset(
    id: 'pop',
    animIn: 'pop',
    animInMs: 400,
    animOut: 'fade',
    animOutMs: 300,
  ),
  AnimationPreset(
    id: 'spin',
    animIn: 'spin',
    animInMs: 600,
    animOut: 'spin',
    animOutMs: 600,
  ),
];

/// Where the user's own animation presets are kept, owned by the domain and
/// implemented at the edge.
abstract interface class AnimationPresetRepository {
  /// The presets the user saved, oldest first.
  Future<List<AnimationPreset>> all();

  /// Stores [preset], replacing the one with the same id.
  Future<void> save(AnimationPreset preset);

  /// Removes the preset with [id]; nothing happens when there is none.
  Future<void> delete(String id);
}

/// The longest name a saved preset can have.
const int maxPresetNameLength = 40;

/// Saves the animation a clip has as a named preset.
class SaveAnimationPreset {
  /// Creates the use case over the repository and the id source.
  SaveAnimationPreset(this._presets, this._ids);

  final AnimationPresetRepository _presets;
  final IdGenerator _ids;

  /// Saves the animation of [clip] as [name]. A blank name, or a clip that
  /// animates neither side, is refused.
  Future<EditorResult<AnimationPreset>> call({
    required Clip clip,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const Err(EmptyName());
    final preset = AnimationPreset(
      id: _ids.next(),
      name: trimmed.length > maxPresetNameLength
          ? trimmed.substring(0, maxPresetNameLength).trimRight()
          : trimmed,
      animIn: clip.animIn,
      animInMs: clip.animInMs,
      animOut: clip.animOut,
      animOutMs: clip.animOutMs,
    );
    if (preset.isEmpty) return const Err(InvalidAnimation());
    await _presets.save(preset);
    return Ok(preset);
  }
}

/// Gives the animation of a preset to a set of clips at once: one save, so
/// one undo.
class ApplyAnimationPreset {
  /// Creates the use case over [_projects].
  const ApplyAnimationPreset(this._projects);

  final ProjectRepository _projects;

  /// Applies [preset] to the clips [clipIds] of project [projectId]. Sound
  /// and text clips are skipped (a title has its own animation); when none
  /// of the clips can be animated the call is refused.
  Future<EditorResult<Project>> call({
    required String projectId,
    required Iterable<String> clipIds,
    required AnimationPreset preset,
  }) async {
    if (!preset.isValid) return const Err(InvalidAnimation());
    final project = await _projects.find(projectId);
    if (project == null) return Err(ProjectNotFound(projectId));
    final wanted = clipIds.toSet();
    var changed = 0;
    final layers = [
      for (final layer in project.layers)
        layer.withClips([
          for (final clip in layer.clips)
            if (wanted.contains(clip.id) &&
                clip.kind != MediaKind.audio &&
                clip.text == null)
              () {
                changed++;
                return clip.copyWith(
                  animIn: preset.animIn,
                  clearAnimIn: preset.animIn == null,
                  animInMs: preset.animIn == null ? 0 : preset.animInMs,
                  animOut: preset.animOut,
                  clearAnimOut: preset.animOut == null,
                  animOutMs: preset.animOut == null ? 0 : preset.animOutMs,
                );
              }()
            else
              clip,
        ]),
    ];
    if (changed == 0) return const Err(IncompatibleClip());
    final updated = project.withLayers(layers);
    await _projects.save(updated);
    return Ok(updated);
  }
}
