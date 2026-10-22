# 0018. Animation presets and transitions between clips

## Status

Accepted · 2026-10-21

## Context

The user asked for animations between pieces, layers, pictures, titles, video and audio, fade-outs, and presets of animations that can be applied and adjusted. Per-clip entrance and exit animations already exist (`render/animation.rs`, schema v8, `SetClipAnimation`, `AnimationPanel`, built by another session).

## Decision

- **Animation presets.** An `AnimationPreset` is a named pair of an entrance and an exit with their lengths. Eight ship with the app (gentle, quick and cinematic fades, slide through, slide up and down, zoom, pop, spin) and the user can save the animation of any clip under a name. User presets are one JSON list in `app_settings` (`animation_presets`), so there is no table. `ApplyAnimationPreset` gives a preset to the selected clip or, with a switch, to every clip of its layer in one save (one undo); sound and titles are skipped (a title has its own animation). The sliders of the animation panel adjust the result afterwards.
- **Transitions are built from what exists.** A transition joins a clip to the one right before it on its layer (a gap up to 250 ms still counts): the first clip's exit and the second's entrance are set to a matching pair (fade, push in four directions, zoom through, spin, fade and pop), from 0.2 to 2 s on each side, and the sound of both fades the same length unless turned off. On sound layers only the fades are set, which is a fade out and in. `RemoveTransition` clears the join. No engine or schema change was needed, so the planned v9 migration was not made.
- **Limit.** The two sides play one after the other (the first clip leaves, then the second comes in) because clips on a layer do not overlap in time. A true cross-dissolve, with both pictures on screen at once, needs overlapping clips or reading past a clip's end; it is not built.

## Consequences

- Added: `domain/animation_preset.dart`, `domain/clip_transition.dart`, `data/settings_animation_preset_repository.dart`, `presentation/animation_preset_providers.dart`, `presentation/tools/animation_presets.dart`, `presentation/tools/transition_section.dart`, `EditorController.applyAnimationPreset/applyTransition/removeTransition`.
- The two sections are placed in the clip options panel, above the animation panel in `clip_tools.dart`, which another session is redesigning.
