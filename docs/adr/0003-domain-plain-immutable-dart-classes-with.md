# 0003. Domain: Plain immutable Dart classes with manual ==/hashCode/copyWith and no freezed: the package is not declared and AGENTS.md forbids adding one without asking

## Status

Accepted · 2026-10-21 · supersedes ADR 0002

## Context

Build of cutter-editor-domain (domain · from SPEC.md). Builds the editor domain under lib/features/editor/domain: immutable entities (Project, Layer, Clip, MediaAsset, Preset, Template), value objects (TimeRange), an EditorResult/EditorFailure error model, the ports the use cases need, and use cases for trim, split, move, reverse, volume, filter, adjustments, layer ordering, media import, presets and templates. Every use case loads a Project through ProjectRepository, applies one rule and saves it. A failure is returned as an Err value and saves nothing, so the project stays unchanged. Time is integer milliseconds, with a 100 ms minimum clip duration. The domain imports no Flutter, drift or FFI code and adds no packages. Tests use hand-written in-memory fakes of the ports, so they need only flutter_test. The existing presentation and sample-data files are not touched.

## Decision

Architecture: lib/features/editor/domain holds entities and value objects (time_range, media_asset, clip, layer, project, preset, template), the error model (editor_result), the ports (editor_ports) and the use cases (clip_timing_use_cases, clip_settings_use_cases, layer_use_cases, preset_use_cases, instantiate_template). Dependencies run one way: use cases -> ports + entities + editor_result; entities -> time_range, media_asset and editor_result only where noted. The domain never imports data/ or presentation/. Adapters (drift, FFI) and the UI will implement or call these ports and use cases in later builds. Tests live in test/features/editor/domain and use in-memory ports.

- Plain immutable Dart classes with manual ==/hashCode/copyWith and no freezed: the package is not declared and AGENTS.md forbids adding one without asking.
- Expected failures are values: sealed EditorResult<T> (Ok | Err) carrying a sealed EditorFailure hierarchy, matched with exhaustive switch. The domain throws no exceptions for rule violations. This supersedes nothing: it generalizes ADR 0002's EditorOutcome to the domain.
- Use cases are async classes with a call(...) method over ProjectRepository and return Future<EditorResult<...>>. Each does load, apply one rule, save, and saves nothing on Err.
- Layer order: Project.layers index 0 is the top timeline row and the front-most layer in the preview. Clips of a Layer are kept sorted by startMs.
- Trim keeps the timeline position of the surviving frames: the new startMs = old startMs + (newIn - oldIn). A trim that makes the clip overlap a neighbour is rejected with Overlap. A trim shorter than 100 ms is ZeroDuration. A trim outside [0, sourceDurationMs] is TrimOutOfSource.
- Split needs start < atMs < end, strictly inside. The first half keeps the clip id and the second half gets a new id from IdGenerator, with no gap.
- Move: startMs >= 0, the target layer has the same kind as the clip, and overlap on the target layer is rejected (never resolved).
- Reverse is allowed on video clips only. Image and audio clips return NotReversible (Q13 decided for now).
- Adjustments are the confirmed set brightness, contrast and saturation, each in [-1.0, 1.0]. Other keys return UnknownAdjustment (Q4 decided for now).
- Volume is a double in [0.0, 1.0]. The effective volume of a clip is 0 if its layer is muted, otherwise layer.volume * clip.volume.
- Filters apply to video and image clips only. Filter or preset filter data on an audio clip returns IncompatibleClip. A null filterId removes the filter.
- An image import gets its intrinsic duration from MediaAsset.durationMs, which the import adapter sets. The domain does not choose a default.

## Consequences

- Files created: lib/features/editor/domain/time_range.dart, lib/features/editor/domain/media_asset.dart, lib/features/editor/domain/clip.dart, lib/features/editor/domain/layer.dart, lib/features/editor/domain/project.dart, lib/features/editor/domain/editor_result.dart, lib/features/editor/domain/preset.dart, lib/features/editor/domain/template.dart, lib/features/editor/domain/editor_ports.dart, lib/features/editor/domain/clip_timing_use_cases.dart, lib/features/editor/domain/clip_settings_use_cases.dart, lib/features/editor/domain/layer_use_cases.dart, lib/features/editor/domain/preset_use_cases.dart, lib/features/editor/domain/instantiate_template.dart, test/features/editor/domain/in_memory_editor_ports.dart, test/features/editor/domain/time_range_and_project_test.dart, test/features/editor/domain/clip_timing_use_cases_test.dart, test/features/editor/domain/clip_settings_use_cases_test.dart, test/features/editor/domain/layer_use_cases_test.dart, test/features/editor/domain/preset_and_template_use_cases_test.dart
- Later changes follow these decisions; one that reverses a decision gets a new ADR that supersedes this one.
