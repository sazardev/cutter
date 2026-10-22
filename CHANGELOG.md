# Changelog

All notable changes to Cutter. Newest first.

## [0.6.0] - 2026-10-22

### Added
- Timeline on touch: an Arrange menu on the clip bar (snap to the previous or
  next clip, send to start, send to end); a selected clip drags at once with a
  finger, lifted, with its start time; the view scrolls by itself when a clip or
  trim handle is held near an edge; a moved clip slides along its neighbours and
  trims stop at them; touching clips show a gap and a seam mark; trim handles
  are 20 dp.
- Effects gallery: transitions, filters, effects and animation presets as cards
  that are tapped or dragged onto any clip; the Animations tab has the user's
  presets, a whole-layer switch and length sliders; a card held in the air
  plays its motion. The Filters tool shows its filters as the same cards.

### Changed
- Imported sound goes to the project's one sound layer, one after another, and
  a sound layer is made only when there is none; "Add layer" still makes a new
  one on purpose.

### Fixed
- The audio output is opened again every second while playing if the device was
  missing or the stream died, and it reports the device and errors in
  Rendimiento.

## [0.5.2] - 2026-10-22

### Added
- Crashlytics, Analytics and Performance: crashes carry the install ID, the
  stage, breadcrumbs and the engine's frame numbers; export failures are
  reported with the resolution, frame rate and layer count; exports and engine
  startup appear as performance traces (ADR 0021).
- A Firebase App Distribution beta for testers.

### Fixed
- Release builds died at launch: R8 renamed `io.flutter.view.TextureRegistry`
  and irondash's JNI lookup failed with `NoSuchMethodError`.
- Export on Android failed with `EAGAIN`: MediaCodec no longer gets the
  global-header flag, which left the encoder without input buffers after
  FFmpeg's dummy-frame flush; NV12 is tried first and `EAGAIN` is retried.
- A single-ABI APK could install on the wrong device and close at launch; the
  shipped APK carries arm64 and x86_64 and drops the 32-bit libraries.

### Changed
- R8 keeps names in the beta so crash reports are readable without a mapping
  upload; turn `-dontobfuscate` off once the mapping is uploaded from CI.

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
