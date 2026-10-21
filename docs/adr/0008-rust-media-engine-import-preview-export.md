# 0008. Rust media engine: real import, preview, undo and export

## Status

Accepted · 2026-10-21

## Context

Nothing in the editor touched a real file. There was no Rust code: the preview was a text placeholder, the import pickers did not exist and nothing could be exported. The user asked for an editor that actually works, at the level of CapCut or the Google Photos editor, and answered these questions for this build:

- Engine: Rust from the start, as SPEC.md asks (FR-16, M1), not platform plugins.
- Platforms (Q1): Android first, with Linux desktop as the development target.
- Scope: import with a real preview, a responsive redesign of the editor, undo/redo with autosave (Q8, Q16) and MP4 export (Q2).
- Packages: approved: Rust `ffmpeg-next`, `cpal`, `irondash_texture` (with `irondash_engine_context` and `irondash_run_loop`), `crossbeam-channel`, `parking_lot`, `anyhow`; Dart `flutter_rust_bridge`, `irondash_engine_context`, `file_picker`, `permission_handler`.

## Decision

**Engine.** The `rust/` crate `cutter_engine` is reached through Flutter Rust Bridge 2.13. Its modules:

- `media/` decodes with FFmpeg. Video is decoded forward cheaply; it seeks on a backward jump or a jump of more than 1.5 s; a 1 s window serves reverse playback; rotation comes from the display matrix. Audio is resampled to 48 kHz stereo f32 and addressed by sample, so blocks join without clicks.
- `render/` holds the compositor: visual layers drawn back to front over black, each clip fitted inside the canvas. Filters and adjustments become a single colour matrix applied while copying. The mixer applies layer and clip volume and mute.
- `playback/` runs a render thread that publishes frames to a Flutter texture through irondash, with no copies through Dart, and an audio thread that mixes about 128 ms ahead of a `cpal` output. A generation counter drops stale audio after every seek, play or edit. Without an audio device the preview plays silently.
- `export.rs` renders offline to MP4: H.264 (`h264_mediacodec` on Android, `libx264` on Linux, OpenH264 as fallback) plus 192 kb/s AAC.

**Boundary.** The UI only knows `MediaEngine` (`lib/core/engine/media_engine.dart`). The project stays the source of truth in Dart and drift. On every change the engine receives an immutable `Timeline` snapshot (`engine_timeline.dart`). The timeline edits themselves (split, trim, move, delete, duplicate) stay as pure Dart domain functions: they cost microseconds, they already had their tests, and they have to be written to drift anyway. This departs from the letter of FR-16 ("timeline mutation in Rust"). All decoding, composition, effects, mixing and encoding run in Rust, off the UI thread, as NFR-2 asks.

**Import.** The system picker is used: the photo and video picker on Android, the desktop portal on Linux. Without a portal (WSL, for example) the app asks for a path. Every file is probed. Files that cannot be played are named back to the user and not imported. Placement rules (`ImportMedia`):

- Pictures go to the end of the main sequence.
- Sound goes to the playhead, on the first audio layer with room.
- An overlay goes on a new front layer at the playhead.

Images start at 3 s and may be stretched up to 10 min. Files the picker left in a cache directory are moved into the app's `media/` folder.

**Answers.** Q11/Q12: formats are whatever FFmpeg can decode; there is no size limit yet. Q8: undo/redo keeps up to 100 steps for as long as the editor is open (`EditHistory`); each step is a whole immutable `Project`. Q16: every accepted edit is saved to drift at once, so there is nothing to recover after a crash. Q2: MP4 at 720p or 1080p, 30 or 60 fps, written to `~/Videos/Cutter` on desktop and to the app's Movies folder on Android.

**Editor.** It is always dark, so colour can be judged against a neutral surround:

- Phones stack the preview, the transport bar, the timeline and a contextual tool bar.
- Wide windows (840 dp and up, or a landscape medium window) put a properties panel beside the preview.
- The timeline keeps the playhead fixed in the middle and scrolls time under it. It has pinch and button zoom, filmstrip thumbnails and normalised waveforms, trim handles, and long-press (or mouse) moves that snap to the playhead and to clip edges, with haptics.
- Desktop gets keyboard shortcuts: Space, S, Delete, Ctrl+Z/Y, Ctrl+D, Ctrl+I, arrow keys, +/-.

## Consequences

- Verified on Linux (WSLg) in the real app: import, preview frames composed by Rust, real-time playback, overlay, filters, undo, trims with snapping, and a 1080×1920 H.264/AAC export whose frames and sound were checked with ffprobe.
- Not yet built on Android: this machine has no Android SDK or NDK. Android also needs FFmpeg cross-compiled for arm64 (an LGPL build, with `h264_mediacodec` for encoding); `rust_builder` already builds the crate for Android once those are present.
- The canvas is fixed at 1080×1920, 30 fps (`DefaultCanvas`). The `editor_projects` table already has `canvas_width`, `canvas_height` and `fps`, but the domain `Project` does not carry them yet (pending the aspect ratio decision).
- Reversed clips play without sound (Q13). Composition runs on the CPU; a GPU path is the next step for 60 fps on 1080p multi-layer previews (NFR-1 has not been measured on a device).
- The exported file is not added to the Android gallery: that needs a MediaStore plugin, which has not been approved.
- `noClipsHint`, `addLayer…` and the other placeholder strings were removed; `AddLayer` stays in the domain, but the editor no longer offers empty layers.
