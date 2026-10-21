# Cutter

Cutter is a multi-layer video editor for mobile phones and tablets. The UI is Flutter; the product promise is a sustained 60 FPS, with all decode, composition, effect and timeline work handled by a Rust engine over FFI. Data is local-first: drift/SQLite is the source of truth for the UI.

Cutter is an editor only: no feed, no publishing, no cloud processing.

## Scope of this slice

This slice adds persistence and the first editor screen on top of the existing editor domain (see `docs/adr/`).

Included:

- A drift database (`editor_projects`, `editor_layers`, `editor_clips`) that implements the domain `ProjectRepository` port. A save replaces a project's layers and clips in one transaction, so a crash never leaves a half-saved project.
- A Riverpod controller that runs the domain use cases against the playhead and the selected clip: split, move, trim, reverse, volume, filter and adjustments.
- The editor page: timeline (layers as rows, clips as blocks), ruler and playhead, time label, clip inspector, empty state, a retryable load error and localized failure messages. Two panes from 600dp.
- Light and dark Material 3 themes (seed `#6750A4`), and English and Spanish strings (English is the template).
- Screen reader labels for every clip on the timeline.
- The `android/` and `ios/` folders, so the app builds and runs on a phone or a tablet.
- A schema that evolves with a migration step per version, and a test that checks the live schema against the dump of the newest version.

Not included:

- The Rust/FFI engine: the preview canvas is a labelled placeholder.
- Recording, media pickers, presets, templates and export.
- Outbox and sync: they wait on the open question Q10 (local versus network storage) in `SPEC.md`.

## Configuration

`.env` holds the configuration and is compiled into the build; `make setup` copies
`.env.example` to it.

| Key | Meaning |
| --- | --- |
| `DATABASE_PATH` | The file of the database. A relative path resolves against the platform's app-data directory, the only place a phone lets the app write to; an absolute path is taken as it is, for a container. Empty opens `<documents>/cutter.sqlite`. |

## Commands

| Task | Command |
| --- | --- |
| Install dependencies | `flutter pub get` |
| Generate code (drift) | `dart run build_runner build` |
| Generate localizations | `flutter gen-l10n` |
| Generate everything | `make generate` |
| Dump the database schema | `make schema` |
| Run the app | `flutter run` |
| Build the Android package | `make build-apk` |
| Analyze | `flutter analyze` |
| Format | `dart format .` |
| Test | `flutter test` |
| All the checks | `make check` |

Run `flutter pub get`, then `build_runner` and `flutter gen-l10n`, before the first analyze, test or run: the generated files (`*.g.dart`, `lib/l10n/app_localizations*.dart`) are not committed and are always regenerated from their sources. CI runs the same two steps before it analyzes, tests or builds.

`make schema` is the one you run when you change the schema: it writes the dump of the new version, the migration helper and the test that runs the steps. The body of a step belongs in `lib/core/db/migrations/fromNToN+1.dart`, which is never regenerated.

## Layout

```
lib/
  main.dart                      composition root: opens the database, mounts ProviderScope
  app/                           CutterApp and the theme
  core/db/                       AppDatabase (WAL, foreign keys, busy timeout)
    migrations/                  one file per schema version: fromNToN+1.dart
    schema/                      the schema dump of each version
  features/editor/
    domain/                      entities, use cases, repository port
    data/                        drift tables, DAO, DriftProjectRepository
    presentation/                providers, controller, failure messages, timeline, inspector, page
  l10n/                          app_en.arb (template), app_es.arb
android/, ios/                   the platform folders the app ships on
test/                            mirrors lib/
```

Dependency direction: `presentation → domain ← data`. Widgets never touch drift; only `main.dart` opens the database.

## Documents

- `SPEC.md`: requirements (FR/NFR) and the open questions.
- `STACK.md`: stack, layout and engineering rules.
- `DESIGN.md`: M3 Expressive tokens and UI rules.
- `AGENTS.md`: workflow and boundaries for contributors and agents.
