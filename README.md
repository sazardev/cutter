# Cutter

Multi-layer video editor for phones and tablets. This repository holds the **editor interface**: Material 3 Expressive screens for the timeline, preview, clip inspector, media picker, recording, filters, presets and templates. The Rust engine does not exist yet, so every screen runs on sample data.

- Package name: `field_visits` (kept from the foundation; the app title shown is `Cutter`, from `editorTitle` in `lib/l10n/app_en.arb`)
- Minimum Dart SDK: `^3.5.0`, Flutter stable channel

## Editor interface

The app opens on the Editor: a preview canvas, a transport bar (play or pause, time label, playhead slider), a layered timeline with Video, Image and Audio rows, and a toolbar. The toolbar opens the clip inspector, media picker, record sheet, filters, presets and templates.

- **Compact windows (< 600 dp)**: one column, toolbar docked at the bottom, 16 dp margins.
- **Medium and larger**: preview beside the toolbar, timeline below, 24 dp margins.
- Edit rules (trim, split, move, reverse, volume, mute) live in `EditorController` and return an `EditorOutcome`; `EditorPage` turns each outcome into one localized snackbar.
- The project timebase is integer milliseconds. Minimum clip length is 100 ms, a split needs the playhead strictly inside the clip, and a move onto an occupied range is rejected.

## Sample data

Until the Rust engine and the database exist, the interface reads only `lib/features/editor/data/sample_project.dart`:

- a starting project with `Beach.mp4` (video), `Logo.png` (image) and `Song.mp3` (audio);
- sample media, including one unsupported file (`broken.mov`) to show the import error;
- sample filters (including `Noir`), an empty preset list and the `Vlog intro` template;
- permissions: microphone granted, camera denied, so the Record sheet shows both paths.

`EditorController` is the single seam to replace with the FFI engine later. Nothing is persisted yet.

## Theme

| Path | Responsibility |
| --- | --- |
| `lib/app/theme/app_tokens.dart` | Spacing, radii, sizes, window classes and the reduced-motion duration helper |
| `lib/app/theme/app_theme.dart` | `buildLightTheme()` and `buildDarkTheme()` from the DESIGN.md color roles, type scale and component shapes |

Widgets read only `Theme.of(context)`, these constants and `AppLocalizations`; they never use `Color(0x...)`, literal spacing or hardcoded strings. The theme mode follows the system.

## Setup and run

Requirements: Flutter stable on your `PATH`, the [Lefthook](https://github.com/evilmartians/lefthook) binary, and Git.

```sh
make setup
make run
```

`make setup` runs `flutter pub get`, copies `.env.example` to `.env` when missing, runs `flutter gen-l10n` and `lefthook install`. Generated localization files (`lib/l10n/app_localizations*.dart`) are git-ignored and never edited by hand; run `make generate` after changing an ARB file.

## Commands

| Task | Command |
| --- | --- |
| Setup | `make setup` |
| Generate localizations | `make generate` |
| Format | `make format` |
| Check formatting | `make format-check` |
| Analyze | `make analyze` |
| Test | `make test` |
| All gates | `make check` |
| Run the app | `make run` |

`make check` runs `generate`, `format-check`, `analyze` and `test` in that order and stops at the first failure. `make run` passes `--dart-define-from-file=.env`.

## Quality gates

The same gates run locally and in CI:

- `dart format --set-exit-if-changed .`
- `flutter analyze` with zero issues
- `flutter test`: controller rules (`test/features/editor/editor_controller_test.dart`), widget tests at 390 dp and 900 dp in light and dark (`test/features/editor/editor_page_test.dart`) and the smoke test that mounts the app and finds `Cutter`
- `flutter build bundle` in the CI build job

CI has three jobs (`lint`, `test`, `build`), runs on pull requests and pushes to `main`, uses `permissions: contents: read`, cancels superseded runs on the same branch and pins `actions/checkout` to a full commit SHA. Hooks format and analyze staged Dart files and check Conventional Commits; do not bypass them with `--no-verify`.

## Environment file

Configuration is passed at build time with `--dart-define-from-file=.env`. `.env.example` is the only environment file in version control; `.env` and other `.env.*` files are ignored.

```sh
# SQLite database file opened by the local drift database.
DATABASE_PATH=data/app.db
```

`DATABASE_PATH` is **not read by the current code**: no database is opened yet. Values are compiled into the build, so no secret belongs in this file.

## Dependency updates

Renovate extends `config:recommended`, runs weekly before Monday 06:00 UTC, groups Flutter and Dart pub updates, and automerges only patch updates and lockfile maintenance when CI is green. Minor and major updates are reviewed. Never mix a dependency update with a feature change in one commit, and do not add a package without asking first.

## Deliberately not included yet

- **Rust engine over FFI**: decode, composition, effects and real preview frames; the preview canvas is a stand-in drawn from sample clips.
- **Persistence**: drift database, outbox, sync, background sync and networking.
- **Open questions**: export (Q2), undo (Q8), autosave (Q16), layer limits (Q5) and the final adjustment set (Q4) are not decided and are not implemented beyond the UI choices above.
- **State packages**: Riverpod is not declared; state is a `ChangeNotifier`.
- **Router**: the app has one home screen; sheets and pages use `Navigator`.

## Conventions to carry forward

- No visible string is hardcoded: add the key to `app_en.arb` with an `@key` description, then run `flutter gen-l10n`.
- Every interactive control has a spoken label and a 48 dp minimum target; selection is never shown by color alone.
- Motion respects `MediaQuery.disableAnimationsOf`.
- Media work never runs on the Flutter UI thread; it belongs to the Rust engine.
- When the database arrives: every write and its outbox entry in one transaction, client-generated UUID v7 ids, soft deletes, and a migration step with its test for each schema change.
- Dependency direction stays `presentation -> domain <- data`.
