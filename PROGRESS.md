# Progress: cutter-editor-slice

Where the work stands, for whoever goes on with it. Rewritten after every build; `Done` is a log and is kept.

## Now

- Last build: the whole project · ✓ builds, boots and passes its checks · 2026-10-21
- Files: 38 of 38 written (28 in `lib/`, 10 in `test/`) · 5 928 lines
- What it builds: the editor slice of ADR 0004, repaired. A drift database stores projects, layers and clips and implements the domain's `ProjectRepository` port. A Riverpod controller runs the domain use cases against the playhead and the selected clip: split, move, trim, reverse, volume, filter and adjustments. The editor page shows the preview placeholder, the time label, the timeline (layers as rows, clips as blocks), the playhead and the clip inspector, in one pane under 600dp and in two panes above. Domain failures are mapped once to localized messages, with an exhaustive switch. The Rust/FFI engine, recording, import pickers and sync are still out: the preview canvas is a placeholder and the outbox waits on Q10.
- Verified: `flutter analyze` clean, `dart format --set-exit-if-changed .` clean, `flutter test` green (128 tests), `flutter build apk --debug` green, and the app installed and driven on an Android 16 emulator: it boots to the empty state, loads a project, selects a clip, seeks and splits it, and the split reaches the database.
- The database schema is dumped to `lib/core/db/schema/cutter/drift_schema_v1.json` and a test checks the live schema against it, so the next schema change has to come with a migration step.
- To resume: `make setup`, then `make check`, then `flutter run`.

## Done

- 2026-10-21 · repair · ✓ built · 38 files · checks pass · the project compiles again after three builds had been layered on each other (see ADR 0005)
- 2026-10-21 · domain · ✓ built · 20 files · checks pass · $3.673
- 2026-10-21 · design · ✓ built · 23 files · checks pass · $6.107
- 2026-10-21 · foundation · ✓ built · 14 files · checks pass · $0.000
- nothing finished yet

## Open

- the `source_duration_ms` of a clip is not stored: the repository rebuilds it from `out_point_ms`, so a trimmed clip forgets how long its source was. Fixing it needs a column and a migration, and the schema is not to be changed without asking.
- `DATABASE_PATH` in `.env` is not honoured: the app opens the database in the platform's app-data directory, the only writable place on a phone. STACK.md asks for a path from configuration for the container deployment.
- there is no `lib/core/db/migrations/` yet: `schemaVersion` is 1 and the schema has never shipped, so the first real change can still edit it in place. The schema dump and the test that locks it are in place, so the change will produce a migration step.
- SPEC.md has 16 open questions: the build decided them in its plan, the answer is yours.

## Next

- FR-16 Rust engine over FFI. The system must perform all media decode, composition, effect application and timeline mutation in the Rust engine, exposed to Flutter through FFI.: no test proves it yet
- FR-3 Music and audio layers. The system must place music and audio files on audio layers.: no test proves it yet
- FR-5 Camera video capture. The system must record video from the device camera and place it on a video layer.: no test proves it yet
