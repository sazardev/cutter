// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:cutter/features/editor/domain/media_asset.dart';

/// One layer a template creates: its display name and the kind of media it
/// holds.
class TemplateLayer {
  /// Creates a template layer.
  const TemplateLayer({required this.name, required this.kind});

  /// Display name of the layer.
  final String name;

  /// Kind of media the layer holds.
  final MediaKind kind;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TemplateLayer && other.name == name && other.kind == kind;

  @override
  int get hashCode => Object.hash(name, kind);
}

/// A place in a template where the user must supply media.
///
/// [layerIndex] points into [Template.layers]; the clip created from the
/// chosen media starts at [startMs] and lasts at most [durationMs].
class MediaSlot {
  /// Creates a media slot.
  const MediaSlot({
    required this.id,
    required this.layerIndex,
    required this.kind,
    required this.startMs,
    required this.durationMs,
  });

  /// Unique id of the slot within its template.
  final String id;

  /// Index into [Template.layers] of the layer the slot belongs to.
  final int layerIndex;

  /// Kind of media the slot accepts.
  final MediaKind kind;

  /// Start of the created clip on the timeline, in milliseconds.
  final int startMs;

  /// Maximum duration of the created clip, in milliseconds.
  final int durationMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaSlot &&
          other.id == id &&
          other.layerIndex == layerIndex &&
          other.kind == kind &&
          other.startMs == startMs &&
          other.durationMs == durationMs;

  @override
  int get hashCode => Object.hash(id, layerIndex, kind, startMs, durationMs);
}

/// A reusable layout of layers and expected media slots from which a new
/// project is created.
class Template {
  /// Creates a template.
  const Template({
    required this.id,
    required this.name,
    required this.layers,
    required this.slots,
  });

  /// Unique id of the template.
  final String id;

  /// Display name of the template.
  final String name;

  /// The layers a project created from this template starts with.
  final List<TemplateLayer> layers;

  /// The media the user must supply.
  final List<MediaSlot> slots;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Template &&
          other.id == id &&
          other.name == name &&
          _listEquals(other.layers, layers) &&
          _listEquals(other.slots, slots);

  @override
  int get hashCode =>
      Object.hash(id, name, Object.hashAll(layers), Object.hashAll(slots));
}

bool _listEquals<E>(List<E> a, List<E> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
