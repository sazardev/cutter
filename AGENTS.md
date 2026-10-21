# AGENTS.md: cutter

## Project
Cutter is a multi-layer video editor for mobile phones and tablets, aimed at creators who record and cut short layered videos on a phone (P1) and at tablet editors who build longer compositions with music, voice-over, images and filters (P2). The UI is Flutter; all decode, composition, effect and timeline work runs in a Rust engine reached over FFI, with a hard performance contract: sustained 60 FPS, no frame over the 16.67 ms budget. Data is local-first: drift/SQLite is the source of truth for the UI, writes go through an outbox, and a sync engine reconciles with the server. The product is an editor only — no feed, no publishing, no cloud processing.

## Read first
- [SPEC.md](SPEC.md): what is being built, the FR/NFR acceptance criteria, and the open questions (Q1–Q16) that still gate scope.
- [STACK.md](STACK.md): the stack, the project layout and the engineering rules every change follows (outbox, soft deletes, conflict policy, dependency direction).
- [DESIGN.md](DESIGN.md): the design system: M3 Expressive tokens, type scale, spacing, window size classes and UI rules.

Then read the code around a change before writing: the DAO, the repository, the sync adapter and the widget you are about to touch.
- [docs/adr/README.md](docs/adr/README.md): why the code is the way it is (architecture decisions).
- [PROGRESS.md](PROGRESS.md): where the work stands: the last build, what is open, what is next.

## Commands
| Task | Command |
| --- | --- |
| Install dependencies | `flutter pub get` |
| Generate code (drift, freezed, riverpod, json) | `dart run build_runner build --delete-conflicting-outputs` |
| Watch generated code | `dart run build_runner watch --delete-conflicting-outputs` |
| Generate localizations | `flutter gen-l10n` |
| Run the app | `flutter run` |
| Analyze (typecheck + lint) | `flutter analyze` |
| Format | `dart format .` |
| Check formatting (CI) | `dart format --set-exit-if-changed .` |
| All tests | `flutter test` |
| One test file | `flutter test test/features/visits/local_visits_repository_test.dart` |
| One test by name | `flutter test --plain-name "writes row and outbox in one transaction"` |
| Build Android | `flutter build apk --flavor <flavor>` |
| Build iOS | `flutter build ipa --flavor <flavor>` |

TODO: the repository currently holds only `DESIGN.md`, `SPEC.md`, `STACK.md` — there is no `Makefile`, `scripts/` or `pubspec.yaml` yet. The commands above come from the Flutter toolchain and from the CI job names in STACK.md (`lint` = format + lint + typecheck, `test`, `build`); confirm them against `.github/workflows/ci.yml` and `lefthook.yml` once they exist.

## Layout
Top level today: `DESIGN.md`, `SPEC.md`, `STACK.md`. The application tree below is the target structure from STACK.md; create files where it says, not elsewhere.

- `lib/main.dart` — opens the database, registers background sync, mounts `ProviderScope`.
- `lib/app/` — `app.dart`, `router.dart`, `theme/`.
- `lib/core/db/` — `app_database.dart` (`@DriftDatabase`), `migrations/` (one step per schema version), `tables/outbox_table.dart`, `tables/sync_state_table.dart`.
- `lib/core/sync/` — `sync_engine.dart` (push → pull → apply, one run at a time), `push_outbox.dart`, `pull_changes.dart`, `conflict_policy.dart`, `background_sync.dart`, `sync_status.dart`.
- `lib/core/network/api_client.dart` — dio plus interceptors.
- `lib/features/<feature>/` — `domain/` (entity, repository interface), `data/` (drift table, DAO, local repository, sync adapter), `presentation/` (controller, page). `visits/` is the reference feature.
- `lib/l10n/` — `app_en.arb` (template), one `app_<lng>.arb` per language; configured by `l10n.yaml`.
- `test/` — mirrors `lib/`.
- `migrations/` — numbered, forward-only SQL migrations. `data/app.db` (+ `-wal`, `-shm`) is git-ignored.

Dependency direction: `presentation → domain ← data`. `core/sync` reaches per-feature sync adapters through an interface and never imports `presentation`. The UI reads only the local database; only `core/sync` talks to the API.

## Conventions
- Every write is one drift transaction: local row change plus outbox entry. Features never call the API directly.
- Deletes are soft (`deleted` flag) until the server confirms, then the row is purged.
- Every synced table has `id` (client-generated UUID v7), `updated_at` (server time when known) and `version` for conflict detection.
- Conflict resolution lives in `conflict_policy.dart` and nowhere else; document the rule when you change it.
- Sync state is the sealed `synced | pending | failed(error)`; use exhaustive `switch`, no booleans for status.
- Entities and DTOs are `freezed` + `json_serializable`; keep API payload mapping in the feature's `*_sync_adapter.dart`.
- One file = one responsibility, named for what it holds (`visits_dao.dart`, not `helpers.dart`).
- UI: ask for M3 roles (`primary`, `surface-container-high`), never raw hex; no hardcoded user-facing strings — every string is an ARB key in `lib/l10n/app_en.arb` with an `@key` description; 4dp grid, 8dp layout; 16dp margins on compact, 24dp on medium and up.
- Tests live in `test/`, mirror the `lib/` path, use the drift in-memory database, `mocktail` and `fake_async`; sync logic must be tested without a network.

## Workflow
1. Find the requirement in SPEC.md (FR/NFR id) and the matching rule in STACK.md. If the requirement depends on an unresolved question (Q2 export, Q5 layer limit, Q12 formats, Q15 permissions, Q16 autosave), stop and ask.
2. Read the code and tests around the change before writing any.
3. Write a failing test first for the behaviour, in `test/` mirroring the `lib/` path.
4. Implement in the right layer: `data` for persistence and outbox, `domain` for the interface, `presentation` for UI. Media work goes to the Rust engine over FFI, never to the Flutter UI thread.
5. Regenerate: `dart run build_runner build --delete-conflicting-outputs`, and `flutter gen-l10n` after touching ARB files.
6. Verify: `dart format .`, `flutter analyze`, `flutter test` — all clean.
7. Commit with Conventional Commits (`feat(timeline): split clip at playhead`, `fix(sync): keep outbox order on retry`). One logical change per commit; the lefthook pre-commit runs format and lint on staged files.

## Boundaries
- Never edit generated files: `*.g.dart`, `*.freezed.dart`, `lib/l10n/app_localizations*.dart`. Change the source and regenerate.
- `pubspec.lock` is not hand-edited; dependency updates come through Renovate. Do not add a package without asking first.
- Never commit `data/app.db`, `-wal` or `-shm`, build outputs, or any secret, API key or signing material.
- Never edit an applied migration. Add a new numbered step and a `fromNToN+1.dart` in `lib/core/db/migrations/`.
- Never make a feature talk to the API, or make the UI wait on the network; the UI reads the database only.
- Never block the Flutter UI thread with decode, compose, filter or timeline-mutation work; never reimplement in Dart what belongs in the Rust engine.
- No raw colors, no hardcoded strings, no one-off spacing values outside the 4/8dp scale.
- No unrelated rewrites, renames or reformatting inside a task; keep the diff to the change.
- Ask before: adding a dependency, changing the conflict policy, changing the schema, touching the sync protocol, or deciding anything an open question in SPEC.md leaves open.

## Definition of done
- The change maps to a specific SPEC.md requirement (or a recorded answer to an open question).
- `flutter analyze` clean, `dart format --set-exit-if-changed .` clean, `flutter test` green.
- New behaviour has a test in `test/`; sync and repository changes are tested against the in-memory drift database.
- Generated code is regenerated, never hand-edited; ARB changes are in every supported locale via `flutter gen-l10n`.
- Writes still go row + outbox in one transaction; deletes stay soft; the sync badge shows the new state.
- No frame-budget regressions: media work stays in Rust, the UI thread does no I/O or decoding.
- DESIGN.md tokens are respected (roles, type scale, spacing, window size classes, light and dark).
- STACK.md, DESIGN.md and SPEC.md still describe the code; update them in the same diff when a rule or a token changes.
- The diff contains only what the task needs.
- TODO: define the CI green-gate explicitly once `.github/workflows/ci.yml` exists (job names, caching, required checks).
