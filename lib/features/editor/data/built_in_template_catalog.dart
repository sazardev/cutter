import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/template.dart';

/// Ids of the templates that ship with the app. The presentation layer maps
/// each id to its localized title and description.
abstract final class BuiltInTemplateIds {
  /// A vertical story: one video layer over a music layer.
  static const verticalStory = 'vertical-story';

  /// A voice-over: a video layer, an image layer and a narration layer.
  static const voiceOver = 'voice-over';

  /// A photo montage: an image layer over a music layer.
  static const photoMontage = 'photo-montage';
}

const _storyDurationMs = 15000;

/// The templates built into the app (Q9: built-in, not downloadable).
class BuiltInTemplateCatalog implements TemplateCatalog {
  /// Creates the catalog.
  const BuiltInTemplateCatalog();

  static const _templates = [
    Template(
      id: BuiltInTemplateIds.verticalStory,
      name: 'Vertical story',
      layers: [
        TemplateLayer(name: 'Video', kind: MediaKind.video),
        TemplateLayer(name: 'Music', kind: MediaKind.audio),
      ],
      slots: [
        MediaSlot(
          id: 'story-video',
          layerIndex: 0,
          kind: MediaKind.video,
          startMs: 0,
          durationMs: _storyDurationMs,
        ),
        MediaSlot(
          id: 'story-music',
          layerIndex: 1,
          kind: MediaKind.audio,
          startMs: 0,
          durationMs: _storyDurationMs,
        ),
      ],
    ),
    Template(
      id: BuiltInTemplateIds.voiceOver,
      name: 'Voice-over',
      layers: [
        TemplateLayer(name: 'Image', kind: MediaKind.image),
        TemplateLayer(name: 'Video', kind: MediaKind.video),
        TemplateLayer(name: 'Narration', kind: MediaKind.audio),
      ],
      slots: [
        MediaSlot(
          id: 'voice-image',
          layerIndex: 0,
          kind: MediaKind.image,
          startMs: 0,
          durationMs: _storyDurationMs,
        ),
        MediaSlot(
          id: 'voice-video',
          layerIndex: 1,
          kind: MediaKind.video,
          startMs: 0,
          durationMs: _storyDurationMs,
        ),
      ],
    ),
    Template(
      id: BuiltInTemplateIds.photoMontage,
      name: 'Photo montage',
      layers: [
        TemplateLayer(name: 'Photos', kind: MediaKind.image),
        TemplateLayer(name: 'Music', kind: MediaKind.audio),
      ],
      slots: [
        MediaSlot(
          id: 'montage-photo',
          layerIndex: 0,
          kind: MediaKind.image,
          startMs: 0,
          durationMs: _storyDurationMs,
        ),
        MediaSlot(
          id: 'montage-music',
          layerIndex: 1,
          kind: MediaKind.audio,
          startMs: 0,
          durationMs: _storyDurationMs,
        ),
      ],
    ),
  ];

  @override
  Future<List<Template>> all() async => _templates;

  @override
  Future<Template?> find(String id) async {
    for (final template in _templates) {
      if (template.id == id) return template;
    }
    return null;
  }
}
