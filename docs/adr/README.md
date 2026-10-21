# Architecture decisions

Why the code is the way it is: one record per decision, never edited after it is accepted (a new one supersedes it).

| ADR | Decision | Date | Status |
|---|---|---|---|
| [0001](0001-foundation-use-field-visits-as-the.md) | Foundation: Use field_visits as the Dart package name and 'Field Visits' as the localized display name; the appTitle ARB key is the single source of visible text | 2026-10-21 | accepted |
| [0002](0002-design-no-new-packages-state-is.md) | Design: No new packages: state is a ChangeNotifier (EditorController) listened to with ListenableBuilder, because AGENTS.md forbids adding a dependency without asking and Riverpod is not declared | 2026-10-21 | superseded by [0003](0003-domain-plain-immutable-dart-classes-with.md) |
| [0003](0003-domain-plain-immutable-dart-classes-with.md) | Domain: Plain immutable Dart classes with manual ==/hashCode/copyWith and no freezed: the package is not declared and AGENTS.md forbids adding one without asking | 2026-10-21 | accepted |
| [0004](0004-cutter-editor-slice-assumes-the-domain-files-named.md) | Cutter-editor-slice: Assumes the domain files named in ADR 0003 exist under lib/features/editor/domain: ProjectRepository (load(id) -> Future<Project?>, save(Project) -> Future<void>), the use cases split, trim, move, reverse, volume, filter and adjust (each a class with call(...) returning Future<EditorResult<Project>>), and IdGenerator | 2026-10-21 | superseded by [0005](0005-remove-the-superseded-design-build-presentation.md) |
| [0005](0005-remove-the-superseded-design-build-presentation.md) | Remove the superseded design-build presentation and make the data layer implement the domain's port | 2026-10-21 | accepted |
| [0006](0006-database-schema-migrations-and-configuration.md) | Database: the schema evolves with a migration step per version, and the file comes from the configuration | 2026-10-21 | accepted |
| [0007](0007-home-onboarding-and-project-creation.md) | Home, onboarding and project creation: the app opens on a project list, and the first launch shows an introduction | 2026-10-21 | accepted |
| [0008](0008-rust-media-engine-import-preview-export.md) | Rust media engine: real import, preview, undo/redo with autosave, and MP4 export; a dark, responsive editor with a CapCut-style timeline | 2026-10-21 | accepted |
| [0009](0009-canvas-framing-versions-inline-tools.md) | Canvas formats, clip framing (move/scale/rotate/opacity/mirror/fill), saved versions with draft status, inline tool panels instead of dialogs, engine diagnostics | 2026-10-21 | accepted |
| [0010](0010-clip-editors-library-presets-performance.md) | Clip editors (video, image, audio), video library, platform and quality export presets, crop/speed/fades (schema 5), auto adjust, and measured performance budgets | 2026-10-21 | accepted |
| [0011](0011-media-bank-picker-rail-layouts.md) | Media bank per project with recents (schema 6), media-filtered system picker with an in-app browser fallback, collapsible side bar, timeline below/above/beside | 2026-10-21 | accepted |
| [0012](0012-appearance-settings.md) | Appearance settings: theme mode, Material You / palette / custom color, corner style and text size, persisted in `app_settings` | 2026-10-21 | accepted |
| [0013](0013-autosave-restore-points-rename-preview-handles.md) | Restore points saved automatically, rename in place, handles on the preview, timeline starting at the left | 2026-10-21 | accepted |
| [0014](0014-home-redesign-guide-filters-covers.md) | Home redesign: guided new project, search with suggestions, sort and filter modal, pinned section, first-frame covers, delete | 2026-10-21 | accepted |
| [0015](0015-offline-music-packs.md) | Offline music packs: genre zips from a hosted catalog, downloaded, unpacked and kept on the device; `tool/music_packs` builds them | 2026-10-21 | accepted |
| [0016](0016-capture-safe-media-backup.md) | Capture (photo, video, voice), every file kept by the app, import limits that warn, relinking missing media, project backup and restore | 2026-10-21 | accepted |
