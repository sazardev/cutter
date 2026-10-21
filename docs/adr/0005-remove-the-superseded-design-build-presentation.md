# 0005. Remove the superseded design-build presentation and make the data layer implement the domain's port

## Status

Accepted · 2026-10-21 · supersedes the presentation layer of [0002](0002-design-no-new-packages-state-is.md)

## Context

Three builds had been layered on top of each other and none of them cleaned up after itself.

- ADR 0002 (design) built a `ChangeNotifier EditorController` over sample data, with a `widgets/` folder and six sheets and pages (media picker, record, filters, presets, templates, clip inspector). It defined its own `EditorOutcome` enum and its own ARB keys.
- ADR 0003 (domain) built the real domain: immutable entities, the `EditorResult`/`EditorFailure` model, the ports in `editor_ports.dart` and the use cases. It did not touch the presentation files.
- ADR 0004 (editor-slice) added persistence and a Riverpod controller, and wrote new `presentation/timeline_view.dart` and `presentation/clip_inspector.dart` against the ADR 0003 domain. It replaced `editor_controller.dart` and `editor_page.dart` with versions that speak the new domain, but it never removed the ADR 0002 files, and it left behind the other half of its own work: the new `timeline_view.dart` and `clip_inspector.dart` were still written against the ADR 0002 controller API.

The result was a repository that did not compile: 364 analyzer issues, 7 failing tests, and two files named `timeline_view.dart` and two named `clip_inspector` in the same package with different APIs. The slice build also created `domain/project_repository.dart`, a second `ProjectRepository` port with `load()` that contradicted ADR 0003's `find()`, and wired the data layer to it, so the use cases and the repository spoke different languages. The repository had no `android/` or `ios/` folder, so `flutter run` and `flutter build apk` were impossible.

The domain of ADR 0003 is the accepted core and is the only part with a passing test suite, so it is what the rest of the code has to fit.

## Decision

The ADR 0004 slice is the app. The ADR 0002 presentation is dead code and is removed rather than ported: the features it represented (recording, media import, presets, templates) are out of the slice's scope, and recording needs the Rust engine (FR-16) that does not exist yet.

- Delete the superseded presentation files: `presentation/widgets/` (preview canvas, clip tile, timeline, transport bar, toolbar) and the sheets and pages for the clip inspector, filters, media picker, presets, record and templates. Delete the sample data (`data/sample_models.dart`, `data/sample_project.dart`) and the two tests written against the old controller. The slice keeps `editor_page.dart`, `timeline_view.dart` and `clip_inspector.dart`.
- There is one `ProjectRepository` port: the one in `domain/editor_ports.dart`, with `find(id)`. `domain/project_repository.dart` is deleted and `DriftProjectRepository` implements the domain's port, so the use cases and the repository speak the same language.
- The presentation layer is the six files of the slice. `editor_providers.dart` is the only place that wires the domain use cases to their ports, and it imports the use cases from the files ADR 0003 actually created (`clip_timing_use_cases`, `clip_settings_use_cases`) instead of the per-use-case files ADR 0004 had assumed.
- `failure_message.dart` maps a failure to text with an exhaustive `switch` over the sealed `EditorFailure`, so a new failure in the domain without a message is a compile error rather than a silent generic message.
- The editor page reads the project through `editorProjectProvider` instead of building the DAO itself, so no widget imports the data layer.
- The repository gets `android/` and `ios/` folders, so the app can be built and run. CI runs `dart run build_runner build` before analyzing and testing, because the generated drift code is not committed, exactly like the generated localizations.
- The database schema is dumped to `lib/core/db/schema/cutter/drift_schema_v1.json` with `dart run drift_dev make-migrations`, and a test checks the live schema against that dump. `build.yaml` names the database for the drift tooling. The dump is what the next schema change turns into a migration step and a generated migration test.

## Consequences

- Files deleted: the five files of `presentation/widgets/`, the six sheets and pages, `data/sample_models.dart`, `data/sample_project.dart`, `domain/project_repository.dart`, `test/features/editor/editor_controller_test.dart` and `test/features/editor/editor_page_test.dart`.
- Files changed: `presentation/editor_providers.dart`, `presentation/editor_controller.dart`, `presentation/editor_page.dart`, `presentation/failure_message.dart`, `data/drift_project_repository.dart`, `test/smoke_test.dart`, the three presentation tests, `Makefile`, `.github/workflows/ci.yml`, `.gitignore`, `.env.example`.
- Files added: the `android/` and `ios/` folders, `build.yaml`, the schema dump and `test/core/db/app_database_schema_test.dart`.
- The transport bar, the toolbar, the media picker, the record sheet, the presets and the templates are gone from the app. They have to be rebuilt on the domain and the Rust engine, not revived from the design build.
- The `Clip.sourceDurationMs` of a clip is not stored: the repository reconstructs it from `out_point_ms`, so a trimmed clip loses the length of its source. Fixing it needs a column and a migration, and the schema is not to be changed without asking.
