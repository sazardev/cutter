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
