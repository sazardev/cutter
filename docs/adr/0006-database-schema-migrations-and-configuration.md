# 0006. Database: the schema evolves with a migration step per version, and the file comes from the configuration

## Status

Accepted · 2026-10-21

## Context

Two problems were open after the repair of ADR 0005.

The first was a data-loss bug. `Clip.sourceDurationMs` is the full duration of the media a clip plays. The repository did not store it: it rebuilt it from `out_point_ms`, which is the same number for a clip that was never trimmed and the wrong one for a clip that was. A trimmed clip therefore forgot how long its source was, and `TrimOutOfSource` could no longer tell a trim that goes past the end of the source from one that does not. The schema had to change, and the project had no migration infrastructure at all: `schemaVersion` was 1, there was no `lib/core/db/migrations/`, and no test covered the schema.

The second was the configuration. `.env.example` and STACK.md both promise that the path of the database comes from `DATABASE_PATH`, and the Makefile passes `--dart-define-from-file=.env` to `flutter run`. Nothing read it: the app always opened `<documents>/cutter.sqlite`. A relative path is also the only thing that can work on a phone, because the working directory of an Android process is not writable, so the rule for resolving it had to be written down.

## Decision

The database is at version 2. `editor_clips` has a nullable `source_duration_ms` column that holds the duration of the source media, and the repository writes it and reads it back. The column is nullable because the rows of version 1 do not have it; for those, the repository falls back to the out point, which is what version 1 did.

Every schema change is a numbered step in `lib/core/db/migrations/`, one file per version pair, and it is wired into the database through the helper that drift generates. `dart run drift_dev make-migrations` writes the schema dump of the new version, the helper with the shapes of the versions, and the test that runs every step; the body of a step lives in its own file and is never regenerated.

The schema dump is the source of truth of the migrations and a test compares the live schema of the database against the newest dump, so a change of the schema that does not come with a dump fails. The migration test checks that the rows of the previous version survive the step.

The file of the database comes from `DATABASE_PATH`. A relative path resolves against the platform's app-data directory, the only place a phone lets the app write to, and the directory is created when it is missing. An absolute path is taken as it is, which is what the container deployment of STACK.md needs. With nothing configured, the app opens `<documents>/cutter.sqlite`. The file is opened in a background isolate, so the user interface thread never waits for SQLite.

## Consequences

- Files added: `lib/core/db/migrations/from1To2.dart`, `lib/core/db/app_database.steps.dart` (generated), the schema dumps of versions 1 and 2, the generated test helpers, `test/core/db/cutter/migration_test.dart`, `test/core/db/app_database_schema_test.dart` and `test/core/db/app_database_path_test.dart`.
- Files changed: `lib/core/db/app_database.dart`, `lib/features/editor/data/tables/editor_tables.dart`, `lib/features/editor/data/drift_project_repository.dart`, `Makefile`, `.env.example`.
- The schema is at version 2 and has never shipped, so the step from 1 to 2 is the only one. The next change adds version 3 and its step, and the migration test grows a case for it.
- A trimmed clip keeps the duration of its source, so a trim can be undone and a trim past the end of the source is still rejected. The repository test covers it.
- `DATABASE_PATH` is read at compile time, like every other value of `.env`: changing it needs a new build. `make run` and `make build-apk` pass the file.
