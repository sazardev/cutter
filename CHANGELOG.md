# Changelog

All notable changes to Cutter. Newest first.

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
