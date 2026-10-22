# Progress: cutter-editor-slice

Where the work stands, for whoever goes on with it. Rewritten after every build; `Done` is a log and is kept.

## Now

- Last build: restore points, rename, preview handles, timeline from the left (ADR 0013); before it: media bank (schema 6), filtered picker with in-app browser, collapsible side bar, timeline below/above/beside (ADR 0011) · ✓ format clean, editor and core analyze clean, 254 Flutter tests and 37 Rust tests green · 2026-10-21 · driven on Linux (WSLg) at 1280x800, 900x412 and 412x900, not yet on Android
- Text layers (ADR 0017, FR-18, schema 7): the engine draws text from nine bundled fonts; Text tool with words, font, size, colour, outline, shadow, background, letter spacing, alignment and entrance; drag, pinch and turn in the preview; texts on layers of their own that move, trim, split and chain like clips · ✓ 59 Rust tests, controller, domain, repository, migration and page tests green; not yet driven by hand on a device or exported to check the video
- Image effects, drawing and cutout (ADR 0019, schemas 8 and 9): 11 filters, blur/vignette/grain/pixelate/sharpen sliders, entrance and exit animations per clip, and a Remove background button for pictures (U²-Net-P through `tract`). Tested with fakes and a synthetic picture; not run on a phone and the cost of effects on the 60 fps preview is not measured. Drawing (schema 9): Add layer → Drawing opens a full-screen canvas (palette, thickness, eraser, undo); Done puts it on the timeline as a transparent picture that can be edited again.
- Verified with real material: without a portal (WSL) Add opens the in-app browser, which shows only media (no .js/.zip/.md) with thumbnails; three PNGs picked in order landed on the timeline; the bank listed the 11 files migrated from existing clips with "on the timeline" marks; a tap placed a file; the three layouts and the rail work in landscape and portrait.
- Previous build verified: a 5-min, two-video project with cuts, overlay images and four sound tracks; a 720p export at 4.2x real time.
- Measured (profile build): paused 0% CPU, playing ~250% (about 150% of it software OpenGL in WSL); RSS about 440 MB in the editor.
- To resume: `make setup`, `make check`, `make run`.

## Done

- 2026-10-21 · autosave and preview · ✓ built · automatic restore points, rename in place, handles on the preview, tap no longer plays, timeline starts at the left (see ADR 0013)
- 2026-10-21 · media and layout · ✓ built · media bank with recents, schema v6, filtered picker and media browser, side bar, timeline layouts (see ADR 0011)
- 2026-10-21 · studio and library · ✓ built · clip editors, Your videos, export presets, schema v5, performance budgets (see ADR 0010)
- 2026-10-21 · pro editing · ✓ built · canvas, framing, versions, inline tools, diagnostics, gallery, schema v4 (see ADR 0009)
- 2026-10-21 · engine · ✓ built · Rust media engine, import, preview, undo/redo, export, editor redesign (see ADR 0008)
- 2026-10-21 · home · ✓ built · home, onboarding, create project, add layer, built-in templates, schema v3 (see ADR 0007)
- 2026-10-21 · database · ✓ built · the schema evolves with a migration step per version and the file comes from the configuration (see ADR 0006)
- 2026-10-21 · repair · ✓ built · 38 files · checks pass · the project compiles again after three builds had been layered on each other (see ADR 0005)
- 2026-10-21 · domain · ✓ built · 20 files · checks pass · $3.673
- 2026-10-21 · design · ✓ built · 23 files · checks pass · $6.107
- 2026-10-21 · foundation · ✓ built · 14 files · checks pass · $0.000
- nothing finished yet

## Open

- Android: the APK builds (ADR 0020) but was never run on a phone or an emulator: start it, import, play and export on a device (the JavaVM hand-off to FFmpeg and MediaCodec encoding are the likeliest to need fixes). Release signing key and Play Store signing are not set.
- GPU composition, and pitch-correct speed for sound (sound at another speed is muted).
- Memory stays near its peak after the editor closes (allocator does not return freed pages); measure on a device before acting.
- GPU composition for 1080p multi-layer at 60 fps (NFR-1), measured on a device.
- SPEC.md open questions still unanswered: Q3, Q4 (speed, crop, rotation), Q5, Q6, Q7, Q13, Q14. Q10, Q11, Q12, Q15 and Q16 are answered (ADR 0016, 0013).
- Capture (photo, video, voice), backup and restore are tested with fakes only: try them on a phone (camera screen, microphone permission, an interruption, a full disk).

## Next

- Keyframes for framing, transitions.
- Text: wrap to a width, per-word styling, user fonts.
