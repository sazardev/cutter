# Progress: cutter-editor-slice

Where the work stands, for whoever goes on with it. Rewritten after every build; `Done` is a log and is kept.

## Now

- Last build: the whole project · ✗ no progress in 2 fix rounds (2 in all) · 2026-10-21
- Files: 22 of 22 written · $3.073
- What it builds: This build adds persistence and a first editor screen on top of the existing editor domain (ADR 0003). It does not recreate the domain files. A drift database stores projects, layers and clips and implements the domain's ProjectRepository port. A Riverpod controller runs the domain use cases against the playhead and the selected clip. The editor page shows the timeline (layers as rows, clips as blocks), a playhead, and an inspector for split, reverse, volume and filter. Domain failures are mapped once to localized messages. The Rust/FFI engine, recording, import pickers and sync are out of this build: the preview canvas is a placeholder and the outbox waits on Q10.
- To resume: <leader>aSbb in Neovim (the run is saved), or go on by hand from `Open`

## Done

- 2026-10-21 · domain · ✓ built · 20 files · checks pass · $3.673
- 2026-10-21 · design · ✓ built · 23 files · checks pass · $6.107
- 2026-10-21 · foundation · ✓ built · 14 files · checks pass · $0.000
- nothing finished yet

## Open

- the check `flutter analyze` fails
- ✗ no progress in 2 fix rounds (2 in all)
- SPEC.md has 16 open questions: the build decided them in its plan, the answer is yours

## Next

- FR-3 Music and audio layers. The system must place music and audio files on audio layers.: no test proves it yet (<leader>aSbf builds it)
- FR-5 Camera video capture. The system must record video from the device camera and place it on a video layer.: no test proves it yet (<leader>aSbf builds it)
- FR-16 Rust engine over FFI. The system must perform all media decode, composition, effect application and timeline mutation in the Rust engine, exposed to Flutter through FFI.: no test proves it yet (<leader>aSbf builds it)
