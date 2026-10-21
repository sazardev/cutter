# 0004. Cutter-editor-slice: Assumes the domain files named in ADR 0003 exist under lib/features/editor/domain: ProjectRepository (load(id) -> Future<Project?>, save(Project) -> Future<void>), the use cases split, trim, move, reverse, volume, filter and adjust (each a class with call(...) returning Future<EditorResult<Project>>), and IdGenerator

## Status

Accepted · 2026-10-21

## Context

Build of cutter-editor-slice (the whole project, from AGENTS.md, STACK.md, DESIGN.md and SPEC.md). This build adds persistence and a first editor screen on top of the existing editor domain (ADR 0003). It does not recreate the domain files. A drift database stores projects, layers and clips and implements the domain's ProjectRepository port. A Riverpod controller runs the domain use cases against the playhead and the selected clip. The editor page shows the timeline (layers as rows, clips as blocks), a playhead, and an inspector for split, reverse, volume and filter. Domain failures are mapped once to localized messages. The Rust/FFI engine, recording, import pickers and sync are out of this build: the preview canvas is a placeholder and the outbox waits on Q10.

## Decision

Architecture: presentation -> domain <- data. core/db/app_database.dart owns the drift schema (tables from features/editor/data/tables). data/editor_dao.dart owns queries. data/drift_project_repository.dart implements the domain ProjectRepository port and maps rows to entities and back. presentation/ holds the providers (the composition point that wires the repository to the use cases), the controller, the failure-message mapper, and the views. The domain never imports data or presentation. Widgets read only controller state and the theme; they never touch drift. app/ holds the theme and the MaterialApp. main.dart is the only place that opens the database.

- Assumes the domain files named in ADR 0003 exist under lib/features/editor/domain: ProjectRepository (load(id) -> Future<Project?>, save(Project) -> Future<void>), the use cases split, trim, move, reverse, volume, filter and adjust (each a class with call(...) returning Future<EditorResult<Project>>), and IdGenerator.
- Persistence is drift on SQLite with three tables (editor_projects, editor_layers, editor_clips). Ids are TEXT UUIDs, and clip rows carry a sort key. Adjustments are stored as a JSON TEXT column holding the brightness/contrast/saturation map.
- The repository save is one transaction that replaces the project's layer and clip rows, so a crash never leaves a half-saved project (NFR-7).
- No outbox or sync table in this build: Q10 (local vs network storage) is open and AGENTS.md says to ask before deciding it.
- State uses plain flutter_riverpod providers (NotifierProvider/AsyncNotifier) with no code generation, so no *.g.dart files are planned.
- The controller holds EditorUiState (project, playheadMs, selectedClipId, failureMessageKey), and every use-case Err becomes a transient message key. The mapper in failure_message.dart is the only place that turns an EditorFailure into text.
- The preview canvas is a labelled placeholder until the Rust engine (FR-16) is built. The playhead is moved by tapping the timeline ruler and by +/- buttons, and the controls are reachable without a keyboard.
- All user-facing strings are ARB keys in en and es (Q14 open, so en is the template). Spacing and colors come from the theme only.

## Consequences

- Files created: pubspec.yaml, l10n.yaml, lib/l10n/app_en.arb, lib/l10n/app_es.arb, lib/features/editor/data/tables/editor_tables.dart, lib/core/db/app_database.dart, lib/features/editor/data/editor_dao.dart, lib/features/editor/data/drift_project_repository.dart, lib/features/editor/presentation/failure_message.dart, lib/features/editor/presentation/editor_providers.dart, lib/features/editor/presentation/editor_controller.dart, lib/app/theme/app_theme.dart, lib/features/editor/presentation/timeline_view.dart, lib/features/editor/presentation/clip_inspector.dart, lib/features/editor/presentation/editor_page.dart, lib/app/app.dart, lib/main.dart, test/features/editor/data/drift_project_repository_test.dart, test/features/editor/presentation/editor_controller_test.dart, test/features/editor/presentation/editor_page_test.dart, README.md
- Later changes follow these decisions; one that reverses a decision gets a new ADR that supersedes this one.
