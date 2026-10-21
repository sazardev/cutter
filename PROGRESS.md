# Progress: cutter-editor-domain

Where the work stands, for whoever goes on with it. Rewritten after every build; `Done` is a log and is kept.

## Now

- Last build: domain · ✓ built · 20 files · checks pass · 2026-10-21
- Files: 20 of 20 written · $3.673
- What it builds: Builds the editor domain under lib/features/editor/domain: immutable entities (Project, Layer, Clip, MediaAsset, Preset, Template), value objects (TimeRange), an EditorResult/EditorFailure error model, the ports the use cases need, and use cases for trim, split, move, reverse, volume, filter, adjustments, layer ordering, media import, presets and templates. Every use case loads a Project through ProjectRepository, applies one rule and saves it. A failure is returned as an Err value and saves nothing, so the project stays unchanged. Time is integer milliseconds, with a 100 ms minimum clip duration. The domain imports no Flutter, drift or FFI code and adds no packages. Tests use hand-written in-memory fakes of the ports, so they need only flutter_test. The existing presentation and sample-data files are not touched.

## Done

- 2026-10-21 · domain · ✓ built · 20 files · checks pass · $3.673
- 2026-10-21 · design · ✓ built · 23 files · checks pass · $6.107
- 2026-10-21 · foundation · ✓ built · 14 files · checks pass · $0.000
- nothing finished yet

## Open

- SPEC.md has 16 open questions: the build decided them in its plan, the answer is yours

## Next

- FR-3 Music and audio layers. The system must place music and audio files on audio layers.: no test proves it yet (<leader>aSbf builds it)
- FR-5 Camera video capture. The system must record video from the device camera and place it on a video layer.: no test proves it yet (<leader>aSbf builds it)
- FR-16 Rust engine over FFI. The system must perform all media decode, composition, effect application and timeline mutation in the Rust engine, exposed to Flutter through FFI.: no test proves it yet (<leader>aSbf builds it)
