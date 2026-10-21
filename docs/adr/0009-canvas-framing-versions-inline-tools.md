# 0009. Canvas formats, clip framing, saved versions and an editor without dialogs

## Status

Accepted · 2026-10-21

## Context

With media working end to end (ADR 0008), real use showed what was missing:

- 16:9 material looked small inside the fixed 9:16 canvas.
- Pictures could not be moved or resized.
- Tools opened modal sheets that covered the preview.
- There was no notion of a saved state.
- Nothing showed how the engine was performing.

The user asked for a mobile-first, professional editor (no dialogs or modals; move and arrange pictures; preview, draft and saved modes; tolerance to sudden closes; care for memory, CPU, logs and traceability) and approved:

- schema version 4, with transforms in columns and a versions table;
- "draft + versions" as the meaning of draft and saved;
- the `gal` package for the Android gallery.

## Decision

**Canvas.** `Project.canvas` (`Canvas`: width, height, fps) maps to the `canvas_*` and `fps` columns that already existed. The presets are 9:16, 16:9, 1:1 and 4:5 at 1080 px on the short side, plus 24/30/60 fps (`SetCanvas`, max 3840 px and 120 fps). The engine renders, previews and exports at the project's canvas; export keeps its orientation.

**Framing.** `Clip.transform` (`ClipTransform`):

- position as a fraction of the canvas from its centre;
- scale on top of fit or fill;
- clockwise rotation, opacity and mirror.

Positions are relative, so a picture keeps its place when the canvas shape changes (`SetClipTransform`, scale 0.05–10). Clips also keep their source size. Clips stored before version 4 are measured once when the editor opens; this is not recorded as an edit.

In Rust, an upright picture at its decoded size is copied directly. Anything else is sampled bilinearly through the inverse transform, with opacity. Decoding never goes above the source size or twice the canvas, so a picture zoomed in does not cost a huge frame.

**Versions.** The project itself is the draft and is stored on every edit (ADR 0008). "Save" writes an `editor_versions` row with a JSON snapshot (`project_snapshot_codec.dart`, format 1). In the same transaction it sets `editor_projects.saved_at_ms`. A project is a draft when `updated_at_ms > saved_at_ms`, shown both in the editor's chip and on the home screen. Restoring a version can be undone (the editor records the previous state), so it acts at once with an Undo toast instead of asking.

**No dialogs.** Every tool is an inline panel (`EditorTool`, `activeToolProvider`). On phones it replaces the tool bar; on wide windows it opens in the side panel. The panels are:

- Volume, Filters, Adjust and Framing for the selected clip;
- Format, Versions, Export, Import path and Performance for the project.

Back and Esc close a panel or leave preview mode before the editor.

Export runs in a controller that lives as long as the editor: the panel can close while it renders, and the progress shows in the top bar. On Android the file is then copied into the gallery (album "Cutter").

**Preview.** Tap a picture to select it, or tap elsewhere to play/pause. Drag, pinch and twist move, scale and rotate the selected picture live, snapping to the centre and to quarter turns with haptics; the result is saved when the fingers lift. On desktop the mouse drags and the wheel scales. Preview mode shows only the picture, a scrub bar and the transport.

**Shortcuts.** New ones: Ctrl+S saves a version, Ctrl+E opens export, T opens framing, F toggles preview mode, Home/End jump. Single keys are ignored while a text field has focus.

**Diagnostics.** The engine keeps counters (frames, mean and worst composition time, late frames, open decoders, cache bytes) and a log of 200 lines: file opens with codec and size, decode and open failures, audio device, export start and finish with speed, and panics. Each preview frame runs under `catch_unwind`. Decoders use at most 4 threads each, and the reverse window is capped at 48 MB per reader. The Dart side logs every edit (name, milliseconds, outcome) to `dart:developer` and to a ring of 200 lines. The Performance panel shows both and copies them for bug reports.

## Consequences

- Verified in the Linux app with real material, in a 412×900 portrait window and a 1280×800 landscape one:
  - switching to 16:9;
  - picture-in-picture by wheel and drag; opacity and mirror;
  - versions, with the draft/saved chip;
  - a `kill -9` mid-session, after which the project reopened exactly and `PRAGMA integrity_check` was ok;
  - preview frames at 5.2 ms mean and 22.6 ms worst with 0 late frames at 30 fps;
  - a 1920×1080 export with no decode errors.
- Export of a 1080p composition with a transformed overlay runs at 0.64× real time in the debug build. Bilinear sampling on the CPU is the cost; the GPU path (ADR 0008) remains the next performance step.
- Undo history is still per session; versions are what survives restarts.
- `export_sheet.dart` and the path dialog were removed.
