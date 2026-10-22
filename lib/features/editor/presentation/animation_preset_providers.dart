import 'package:cutter/core/settings/settings_store.dart';
import 'package:cutter/features/editor/data/settings_animation_preset_repository.dart';
import 'package:cutter/features/editor/domain/animation_preset.dart';
import 'package:cutter/features/editor/domain/clip_transition.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the user's animation presets are kept.
final animationPresetRepositoryProvider = Provider<AnimationPresetRepository>(
  (ref) => SettingsAnimationPresetRepository(
    SettingsStore(ref.watch(appDatabaseProvider)),
  ),
);

/// The presets the user saved. Invalidate after saving or deleting one.
final userAnimationPresetsProvider =
    FutureProvider.autoDispose<List<AnimationPreset>>(
  (ref) => ref.watch(animationPresetRepositoryProvider).all(),
);

/// The use case that saves the animation of a clip as a preset.
final saveAnimationPresetProvider = Provider<SaveAnimationPreset>(
  (ref) => SaveAnimationPreset(
    ref.watch(animationPresetRepositoryProvider),
    ref.watch(idGeneratorProvider),
  ),
);

/// The use case that gives a preset's animation to clips.
final applyAnimationPresetProvider = Provider<ApplyAnimationPreset>(
  (ref) => ApplyAnimationPreset(ref.watch(projectRepositoryProvider)),
);

/// The use case that joins a clip to the one before it with a transition.
final applyTransitionProvider = Provider<ApplyTransition>(
  (ref) => ApplyTransition(ref.watch(projectRepositoryProvider)),
);

/// The use case that takes a transition off a join.
final removeTransitionProvider = Provider<RemoveTransition>(
  (ref) => RemoveTransition(ref.watch(projectRepositoryProvider)),
);
