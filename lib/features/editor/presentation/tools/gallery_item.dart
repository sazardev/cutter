import 'package:cutter/features/editor/domain/animation_preset.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/clip_transition.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a card of the effects gallery stands for. A card is dragged onto a
/// clip of the timeline, or tapped to give it to the selected clip.
sealed class GalleryItem {
  const GalleryItem();
}

/// A transition; null [kind] takes the transition off instead.
final class TransitionItem extends GalleryItem {
  /// Creates the item for [kind].
  const TransitionItem(this.kind);

  /// The transition, or null for "no transition".
  final TransitionKind? kind;
}

/// A colour filter; null [id] takes the filter off.
final class FilterItem extends GalleryItem {
  /// Creates the item for filter [id].
  const FilterItem(this.id);

  /// The filter id, or null for "no filter".
  final String? id;
}

/// One of the effects (blur, vignette...), given at [effectDefaultStrength].
final class EffectItem extends GalleryItem {
  /// Creates the item for effect [key].
  const EffectItem(this.key);

  /// One of `effectKeys`.
  final String key;
}

/// An entrance and exit animation preset (see [AnimationPreset]); the empty
/// preset takes the animations off.
final class AnimationPresetItem extends GalleryItem {
  /// Creates the item for [preset].
  const AnimationPresetItem(this.preset);

  /// The preset to give.
  final AnimationPreset preset;
}

/// Strength an effect gets when a card is dropped; the sliders fine tune it.
const double effectDefaultStrength = 0.5;

/// Whether [clip] can take any card of the gallery: transitions, filters and
/// effects all work on the picture, so not on sound and not on a title.
bool galleryAccepts(Clip clip) =>
    clip.kind != MediaKind.audio && clip.text == null;

/// Length, in milliseconds, of the next transition given from the gallery.
final galleryTransitionMsProvider = StateProvider<int>((ref) => 600);

/// Whether the next transition given from the gallery fades the sound too.
final galleryFadeSoundProvider = StateProvider<bool>((ref) => true);

/// The localized name of transition [kind].
String transitionLabel(AppLocalizations l10n, TransitionKind kind) =>
    switch (kind) {
      TransitionKind.dip => l10n.transitionDip,
      TransitionKind.pushLeft => l10n.transitionPushLeft,
      TransitionKind.pushRight => l10n.transitionPushRight,
      TransitionKind.pushUp => l10n.transitionPushUp,
      TransitionKind.pushDown => l10n.transitionPushDown,
      TransitionKind.zoomThrough => l10n.transitionZoomThrough,
      TransitionKind.spin => l10n.transitionSpin,
      TransitionKind.pop => l10n.transitionPop,
    };

/// The localized name of effect [key].
String effectLabel(AppLocalizations l10n, String key) => switch (key) {
      'blur' => l10n.effectBlur,
      'vignette' => l10n.effectVignette,
      'grain' => l10n.effectGrain,
      'pixelate' => l10n.effectPixelate,
      _ => l10n.effectSharpen,
    };
