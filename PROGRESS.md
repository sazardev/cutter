# Progress: Cutter interface

Where the work stands, for whoever goes on with it. Rewritten after every build; `Done` is a log and is kept.

## Now

- Last build: design · ✓ built · 23 files · checks pass · 2026-10-21
- Files: 23 of 23 written · $6.107
- What it builds: Builds the Cutter editor UI as Material 3 Expressive screens on top of the existing Flutter foundation. No domain or engine exists yet, so every screen reads one small sample-data file and a ChangeNotifier EditorController holds only UI state over that sample. The app opens on the Editor: a preview canvas, a transport bar, a layered timeline with a playhead, and a toolbar. The toolbar opens the clip inspector, media picker, record sheet, filters, presets and templates. Colors, type, spacing and shapes come from a theme built once from DESIGN.md tokens. Widgets read only the theme and AppLocalizations; every visible string is an ARB key. The controller is the single seam to swap for the Rust FFI engine later.

## Done

- 2026-10-21 · design · ✓ built · 23 files · checks pass · $6.107
- 2026-10-21 · foundation · ✓ built · 14 files · checks pass · $0.000
- nothing finished yet

## Open

- SPEC.md has 16 open questions: the build decided them in its plan, the answer is yours

## Next

- FR-3 Music and audio layers. The system must place music and audio files on audio layers.: no test proves it yet (<leader>aSbf builds it)
- FR-5 Camera video capture. The system must record video from the device camera and place it on a video layer.: no test proves it yet (<leader>aSbf builds it)
- FR-10 Adjust and modify. The system must expose per-clip adjustment and modification controls on clips and route them through the Rust engine.: no test proves it yet (<leader>aSbf builds it)
- FR-12 Presets. The system must save a set of clip settings as a preset and apply it to other clips.: no test proves it yet (<leader>aSbf builds it)
- FR-13 Templates. The system must create a project from a template.: no test proves it yet (<leader>aSbf builds it)
- FR-16 Rust engine over FFI. The system must perform all media decode, composition, effect application and timeline mutation in the Rust engine, exposed to Flutter through FFI.: no test proves it yet (<leader>aSbf builds it)
