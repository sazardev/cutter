# 0011. Media bank, filtered picker, collapsible side bar and timeline layouts

## Status

Accepted · 2026-10-21

## Context

Importing meant typing a file path, which makes no sense on a phone and is awkward on Linux. The user asked for:

- the system file picker, already filtered to media;
- the kind (video, image, sound) detected, never chosen;
- a bank of imported media to keep adding from;
- the Add tool bar as a side bar that can fold;
- the timeline below, above or beside the preview;
- polish on Android and Linux, in portrait and landscape.

They approved a media bank per project with recent files from other projects (schema version 6), and on Linux an in-app media browser alongside the native portal dialog.

## Decision

**Media bank, schema 6.** The `editor_media` table holds one row per file and project:

- the path, the kind, duration, size, whether it has sound, and when it was added;
- unique on `(project_id, path)`;
- `project_id` is set to null when the project is deleted.

The `from5To6` migration fills it from the clips that already exist. `DriftMediaBank` implements the `MediaBank` port:

- files that no longer exist drop out of the bank;
- `recent` lists each path once, from other projects.

Every import goes into the bank. Import from the bank panel stops there; Add also places the files on the timeline.

**Picking.** `mediaPickerProvider` returns paths:

- **Android:** the document picker, restricted to the extensions in `media/media_formats.dart`.
- **Linux:** the xdg-desktop-portal dialog with the same filter. If there is no portal (WSL, bare window managers), the app remembers that and opens `MediaBrowserPage` from then on. That page has:
  - folder shortcuts and folders first;
  - only media files, with real thumbnails;
  - kind filters and search;
  - multi-select numbered in the order of the taps;
  - the last folder remembered.

The engine still has the last word on each file. Files it rejects are left out without a notice (the app shows no snackbars, see ADR 0013), and the rest are imported.

**Side bar and drawer.** On wide windows (expanded, or medium in landscape) an `EditorRail` holds Add and the project tools (Media, Format, Layout, Versions, Export, Performance):

- A project tool opens in a 360 dp `ToolDrawer` beside the rail.
- Clip properties open in a 340 dp panel on the right.
- The rail shows labels from 1200 dp by default. Ctrl+\ or the toggle at its foot folds it, and the choice is remembered.
- The rail folds to icons by itself while a drawer and the clip panel are both open, so the preview keeps room.
- Labels follow the width actually laid out, so nothing overflows while the rail animates.

On compact windows the same tools sit in the bottom tool bar, and panels open inline below it.

**Timeline layouts.** `TimelinePosition` is `bottom`, `top` or `side`. It is stored in `app_settings` (`editor.timeline_position`, `editor.rail_expanded`) through `SettingsStore`. `side` needs a window at least 600 dp wide; narrow windows fall back to `bottom`, and the Layout panel explains why.

**Shortcuts.** Ctrl+I picks and imports, and Ctrl+B opens the bank.

## Consequences

- No user-facing path entry remains; `import_path_panel.dart` and its strings are gone.
- The bank keeps paths, not copies. Files moved outside the app drop out of the bank, and their clips show as missing, as before.
- Android picking is untested on a device until the SDK and NDK are installed.
- Widget tests replace the picker with a fake and the bank's file check with `exists: (_) => true`. The browser test lists a real temporary folder.
