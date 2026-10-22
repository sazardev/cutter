// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes
// ignore_for_file: no_runtimetype_tostring
// The classes here are immutable (final fields only); `package:meta` is not a
// declared dependency, so `@immutable` is not available to the domain.

/// The outcome of an edit rule: [Ok] with a value or [Err] with a failure.
sealed class EditorResult<T> {
  /// Creates a result.
  const EditorResult();
}

/// The edit rule succeeded and produced [value].
final class Ok<T> extends EditorResult<T> {
  /// Creates a successful result holding [value].
  const Ok(this.value);

  /// The value the edit rule produced.
  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T> && other.value == value;

  @override
  int get hashCode => Object.hash(Ok, value);

  @override
  String toString() => 'Ok($value)';
}

/// The edit rule was rejected; nothing was saved.
final class Err<T> extends EditorResult<T> {
  /// Creates a rejected result carrying [failure].
  const Err(this.failure);

  /// Why the edit rule rejected the command.
  final EditorFailure failure;

  @override
  bool operator ==(Object other) => other is Err<T> && other.failure == failure;

  @override
  int get hashCode => Object.hash(Err, failure);

  @override
  String toString() => 'Err($failure)';
}

/// The reasons an edit rule can reject a command. Failures are values with
/// equality so callers and tests can compare and switch over them.
sealed class EditorFailure {
  /// Creates a failure.
  const EditorFailure();

  /// The values that identify this failure besides its type.
  List<Object?> get props => const [];

  @override
  bool operator ==(Object other) {
    if (other is! EditorFailure || other.runtimeType != runtimeType) {
      return false;
    }
    final mine = props;
    final theirs = other.props;
    if (mine.length != theirs.length) return false;
    for (var index = 0; index < mine.length; index++) {
      if (mine[index] != theirs[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(runtimeType, Object.hashAll(props));

  @override
  String toString() =>
      props.isEmpty ? '$runtimeType()' : '$runtimeType(${props.join(', ')})';
}

/// No project exists with the given id.
final class ProjectNotFound extends EditorFailure {
  /// Creates the failure for project [id].
  const ProjectNotFound(this.id);

  /// The unknown project id.
  final String id;

  @override
  List<Object?> get props => [id];
}

/// No layer exists with the given id.
final class LayerNotFound extends EditorFailure {
  /// Creates the failure for layer [id].
  const LayerNotFound(this.id);

  /// The unknown layer id.
  final String id;

  @override
  List<Object?> get props => [id];
}

/// No clip exists with the given id.
final class ClipNotFound extends EditorFailure {
  /// Creates the failure for clip [id].
  const ClipNotFound(this.id);

  /// The unknown clip id.
  final String id;

  @override
  List<Object?> get props => [id];
}

/// The resulting clip would be shorter than the minimum duration.
final class ZeroDuration extends EditorFailure {
  /// Creates the failure.
  const ZeroDuration();
}

/// The trim points fall outside the source media.
final class TrimOutOfSource extends EditorFailure {
  /// Creates the failure.
  const TrimOutOfSource();
}

/// The split time is not strictly inside the clip.
final class PlayheadOutsideClip extends EditorFailure {
  /// Creates the failure.
  const PlayheadOutsideClip();
}

/// The start time is negative.
final class NegativeStart extends EditorFailure {
  /// Creates the failure.
  const NegativeStart();
}

/// The edit would overlap the clip [otherClipId] on the same layer.
final class Overlap extends EditorFailure {
  /// Creates the failure for the clip [otherClipId].
  const Overlap(this.otherClipId);

  /// The clip that would be overlapped.
  final String otherClipId;

  @override
  List<Object?> get props => [otherClipId];
}

/// The clip or media kind does not match the layer kind.
final class WrongLayerKind extends EditorFailure {
  /// Creates the failure.
  const WrongLayerKind();
}

/// Only video clips can be reversed.
final class NotReversible extends EditorFailure {
  /// Creates the failure.
  const NotReversible();
}

/// A volume outside the range 0.0 to 1.0.
final class InvalidVolume extends EditorFailure {
  /// Creates the failure.
  const InvalidVolume();
}

/// The setting does not apply to this kind of clip.
final class IncompatibleClip extends EditorFailure {
  /// Creates the failure.
  const IncompatibleClip();
}

/// The animation id is not one the engine renders, or its length is out of
/// range.
final class InvalidAnimation extends EditorFailure {
  /// Creates the failure.
  const InvalidAnimation();
}

/// The adjustment key is not part of the confirmed set.
final class UnknownAdjustment extends EditorFailure {
  /// Creates the failure for [key].
  const UnknownAdjustment(this.key);

  /// The unknown adjustment key.
  final String key;

  @override
  List<Object?> get props => [key];
}

/// The adjustment value is outside its allowed range.
final class AdjustmentOutOfRange extends EditorFailure {
  /// Creates the failure for [key].
  const AdjustmentOutOfRange(this.key);

  /// The adjustment key whose value is out of range.
  final String key;

  @override
  List<Object?> get props => [key];
}

/// The media file is unsupported or corrupt.
final class UnsupportedMedia extends EditorFailure {
  /// Creates the failure.
  const UnsupportedMedia();
}

/// The given layer ids are not a permutation of the project layers.
final class InvalidLayerOrder extends EditorFailure {
  /// Creates the failure.
  const InvalidLayerOrder();
}

/// A name is blank.
final class EmptyName extends EditorFailure {
  /// Creates the failure.
  const EmptyName();
}

/// No preset exists with the given id.
final class PresetNotFound extends EditorFailure {
  /// Creates the failure for preset [id].
  const PresetNotFound(this.id);

  /// The unknown preset id.
  final String id;

  @override
  List<Object?> get props => [id];
}

/// No template exists with the given id.
final class TemplateNotFound extends EditorFailure {
  /// Creates the failure for template [id].
  const TemplateNotFound(this.id);

  /// The unknown template id.
  final String id;

  @override
  List<Object?> get props => [id];
}

/// Media slots of the template that were not filled with usable media.
final class MissingTemplateMedia extends EditorFailure {
  /// Creates the failure for the unfilled [slotIds].
  const MissingTemplateMedia(this.slotIds);

  /// The ids of the slots without usable media.
  final List<String> slotIds;

  @override
  List<Object?> get props => slotIds;
}

/// A clip transform is outside its allowed ranges (scale, opacity).
final class InvalidTransform extends EditorFailure {
  /// Creates the failure.
  const InvalidTransform();
}

/// A canvas size or frame rate is not usable.
final class InvalidCanvas extends EditorFailure {
  /// Creates the failure.
  const InvalidCanvas();
}

/// No saved version exists with the given id.
final class VersionNotFound extends EditorFailure {
  /// Creates the failure for version [id].
  const VersionNotFound(this.id);

  /// The unknown version id.
  final String id;

  @override
  List<Object?> get props => [id];
}

/// A speed outside 0.25x to 4x.
final class InvalidSpeed extends EditorFailure {
  /// Creates the failure.
  const InvalidSpeed();
}

/// A fade longer than half the clip, or negative.
final class InvalidFade extends EditorFailure {
  /// Creates the failure.
  const InvalidFade();
}

/// A crop that cuts too much or reaches past the picture.
final class InvalidCrop extends EditorFailure {
  /// Creates the failure.
  const InvalidCrop();
}

/// A drawing has nothing drawn, or the clip is not a drawing.
final class InvalidDrawing extends EditorFailure {
  /// Creates the failure.
  const InvalidDrawing();
}

/// A text has a value outside its allowed range, or the clip is not a text.
final class InvalidText extends EditorFailure {
  /// Creates the failure.
  const InvalidText();
}
