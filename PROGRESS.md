# Progress: cutter-editor-slice

Where the work stands, for whoever goes on with it. Rewritten after every build; `Done` is a log and is kept.

## Now

- Last build: the whole project · ✓ builds, boots and passes its checks · 2026-10-21
- Files: 46 Dart files (30 in `lib/`, 16 in `test/`) · 9 076 lines
- What it builds: the editor slice of ADR 0004, repaired. A drift database stores projects, layers and clips and implements the domain's `ProjectRepository` port. A Riverpod controller runs the domain use cases against the playhead and the selected clip: split, move, trim, reverse, volume, filter and adjustments. The editor page shows the preview placeholder, the time label, the timeline (layers as rows, clips as blocks), the playhead and the clip inspector, in one pane under 600dp and in two panes above. Domain failures are mapped once to localized messages, with an exhaustive switch. The Rust/FFI engine, recording, import pickers and sync are still out: the preview canvas is a placeholder and the outbox waits on Q10.
- The database is at schema version 2: `editor_clips` stores the duration of the source media, so a trimmed clip no longer forgets it. The step from 1 to 2 lives in `lib/core/db/migrations/from1To2.dart`; a test checks the live schema against the dump of the newest version, and the migration test checks that the rows survive the step.
- The file of the database comes from `DATABASE_PATH` in `.env`: a relative path resolves against the app-data directory, an absolute path is taken as it is.
- Verified: `flutter analyze` clean, `dart format --set-exit-if-changed .` clean, `flutter test` green (134 tests), `flutter build apk --debug` green, and the app installed and driven on an Android 16 emulator: it boots to the empty state, loads a project, selects a clip, seeks and splits it, the split reaches the database, and a file written by version 1 is migrated to version 2 on open with its rows intact.
- To resume: `make setup`, then `make check`, then `flutter run`.

## Done

- 2026-10-21 · database · ✓ built · the schema evolves with a migration step per version and the file comes from the configuration (see ADR 0006)
- 2026-10-21 · repair · ✓ built · 38 files · checks pass · the project compiles again after three builds had been layered on each other (see ADR 0005)
- 2026-10-21 · domain · ✓ built · 20 files · checks pass · $3.673
- 2026-10-21 · design · ✓ built · 23 files · checks pass · $6.107
- 2026-10-21 · foundation · ✓ built · 14 files · checks pass · $0.000
- nothing finished yet

## Open

- SPEC.md has 16 open questions: the build decided them in its plan, the answer is yours.

## Next

- FR-16 Rust engine over FFI. The system must perform all media decode, composition, effect application and timeline mutation in the Rust engine, exposed to Flutter through FFI.: no test proves it yet
- FR-3 Music and audio layers. The system must place music and audio files on audio layers.: no test proves it yet
- FR-5 Camera video capture. The system must record video from the device camera and place it on a video layer.: no test proves it yet
