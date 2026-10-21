// All fields are final, so the class is immutable; the `meta` package that
// provides `@immutable` is not a declared dependency of the domain.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:cutter/features/editor/domain/canvas.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/layer.dart';

/// The project aggregate: layers ordered so that index 0 is the top timeline
/// row and the front-most layer in the preview.
class Project {
  /// Creates a project; [layers] are copied into an unmodifiable list.
  Project({
    required this.id,
    required this.name,
    List<Layer> layers = const [],
    this.templateId,
    this.canvas = defaultCanvas,
  }) : layers = List.unmodifiable(layers);

  /// Unique id of the project.
  final String id;

  /// Display name of the project.
  final String name;

  /// The layers, index 0 being the front-most.
  final List<Layer> layers;

  /// Id of the template the project was created from, if any.
  final String? templateId;

  /// The frame the project renders to.
  final Canvas canvas;

  /// The layer with [id], or null when the project has none.
  Layer? layerById(String id) {
    for (final layer in layers) {
      if (layer.id == id) return layer;
    }
    return null;
  }

  /// The clip with [id] on any layer, or null when unknown.
  Clip? clipById(String id) {
    for (final layer in layers) {
      for (final clip in layer.clips) {
        if (clip.id == id) return clip;
      }
    }
    return null;
  }

  /// The layer that holds the clip with [clipId], or null when unknown.
  Layer? layerOfClip(String clipId) {
    for (final layer in layers) {
      for (final clip in layer.clips) {
        if (clip.id == clipId) return layer;
      }
    }
    return null;
  }

  /// Returns a copy where the layer with the same id as [layer] is replaced,
  /// keeping the layer order.
  Project replaceLayer(Layer layer) {
    return withLayers([
      for (final existing in layers)
        if (existing.id == layer.id) layer else existing,
    ]);
  }

  /// Returns a copy holding [newLayers] in the given order.
  Project withLayers(List<Layer> newLayers) {
    return Project(
      id: id,
      name: name,
      layers: newLayers,
      templateId: templateId,
      canvas: canvas,
    );
  }

  /// The project without layers that hold no clip: a layer exists for what
  /// is on it, so an emptied one (or a template's unused one) goes away.
  /// Returns this project when every layer has a clip.
  Project withoutEmptyLayers() {
    if (layers.every((layer) => layer.clips.isNotEmpty)) return this;
    return withLayers([
      for (final layer in layers)
        if (layer.clips.isNotEmpty) layer,
    ]);
  }

  /// Returns a copy called [newName].
  Project withName(String newName) {
    return Project(
      id: id,
      name: newName,
      layers: layers,
      templateId: templateId,
      canvas: canvas,
    );
  }

  /// Returns a copy rendering to [newCanvas].
  Project withCanvas(Canvas newCanvas) {
    return Project(
      id: id,
      name: name,
      layers: layers,
      templateId: templateId,
      canvas: newCanvas,
    );
  }

  /// The largest clip end across all layers, 0 when there are no clips.
  int get durationMs {
    var longest = 0;
    for (final layer in layers) {
      for (final clip in layer.clips) {
        final end = clip.range.endMs;
        if (end > longest) longest = end;
      }
    }
    return longest;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Project &&
          other.id == id &&
          other.name == name &&
          other.templateId == templateId &&
          other.canvas == canvas &&
          _sameLayers(other.layers);

  bool _sameLayers(List<Layer> other) {
    if (other.length != layers.length) return false;
    for (var i = 0; i < layers.length; i++) {
      if (other[i] != layers[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        templateId,
        canvas,
        Object.hashAll(layers),
      );

  @override
  String toString() => 'Project($id, $name, ${layers.length} layers)';
}
