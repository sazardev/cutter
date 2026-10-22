# Changelog

All notable changes to Cutter. Newest first.

## [0.5.1] - 2026-10-21

### Added
- Android build: the first APK (arm64), with FFmpeg cross-compiled and linked into the engine (ADR 0020).
- `tool/android/build_ffmpeg.sh` to build FFmpeg for Android.

### Changed
- Android needs version 8 (API 26) or newer, for the engine's sound output.

## [0.5.0] - 2026-10-21

### Added
- Drawing: Add layer, Drawing opens a full-screen canvas with a palette, thickness, an eraser and undo; it lands on the timeline as a transparent picture that can be edited again (schema 9).
- Remove background for pictures: one button cuts out the subject (U²-Net-P run by `tract`, bundled in the app); undo brings the original back.
- Seven more filters: sepia, noir, vivid, fade, cinema, sunset and invert.
- Effects with live preview: blur, vignette, grain, pixelate and sharpen.
- Entrance and exit animations for any picture or video clip: fade, slides, zoom in and out, spin and pop (schema 8).
- Architecture decision for effects, animations, drawing and background removal (ADR 0019).

### Changed
- The clip options panel lists filters, effects, transitions, animation presets, animations and background in collapsible sections.

### Fixed
- The media panel, storage section and animation presets follow the lint rules (braces, trailing commas).

## [0.4.0] - 2026-10-21

### Added
- Text layers: the engine draws text from nine bundled fonts, with outline, shadow, background, spacing, alignment and an entrance animation (ADR 0017, schema 7).
- Animation presets: eight built in, and your own saved under a name; apply them to one clip or a whole layer.
- Transitions between neighbouring clips built from their animations and sound fades (ADR 0018).

## [0.3.0] - 2026-10-21

### Added
- Capture photo, video and voice with the device; every imported file is kept by the app.
- Import limits that warn, and relinking of media that went missing.
- Back a project up to one file and restore it.
- Storage screen: what Cutter keeps, with cleaning of the cache and of unused media (ADR 0016).

## [0.2.0] - 2026-10-21

### Added
- Logo, launcher icons, splash screen and brand guide.
- Music library: pause, resume and cancel downloads, and manage packs in Settings.

## [0.1.0] - 2026-10-21

First usable build: a full editing flow from the home screen to an exported video.

### Added
- Home with your projects, templates and a first-launch introduction.
- Settings: theme, color (including Material You), corner style, text size, export folder, permissions and share preferences.
- Architecture decisions for the engine, editor, settings and home (ADR 0007-0014).

### Changed
- The editor follows the color and corners you choose in Settings.

## [0.0.3] - 2026-10-21

### Added
- Rust media engine: real import, live preview, undo and redo with autosave.
- Multi-layer timeline with split, trim, move, reverse, volume, filters and adjustments.
- Clip editors for video, image and audio, with crop, speed and fades.
- Canvas formats, clip framing and saved versions of a project.
- Media bank per project with recents and a system picker.
- Export to MP4 with platform and quality presets, and a library of rendered videos.

### Changed
- Database schema migrated to version 6.

## [0.0.2] - 2026-10-21

### Added
- Offline music library: genre packs downloaded from a catalog.
- Workflow that builds and publishes the music packs.

### Fixed
- A clip now stores the duration of its source; `DATABASE_PATH` is honoured.
- CI runs on the branch the repository has.

## [0.0.1] - 2026-10-21

### Added
- Editor scaffold with theme, domain models, use cases and tests.
- Drift persistence and the timeline UI for the editor.

### Fixed
- Presentation layer reconciled with the domain.
