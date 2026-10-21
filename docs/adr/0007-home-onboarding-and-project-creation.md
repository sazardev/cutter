# 0007. Home, onboarding and project creation: the app opens on a project list, and the first launch shows an introduction

## Status

Accepted · 2026-10-21

## Context

The editor was the only screen. It opened the oldest stored project and, with an empty database, showed "No layers yet" with no way to act on it: nothing created a project, nothing added a layer, and a first-time user had no guidance. Three questions of SPEC.md and STACK.md bear on the fix, and the user answered them for this build.

## Decision

The app opens on a home screen. It lists the stored projects (name, layers, duration), creates an empty project, creates a project from a built-in template, and reopens the introduction from a help button. The editor now receives the id of the project it edits.

The introduction is three pages and is shown once. Whether it was seen is stored in a new `app_settings` key/value table (schema version 3, `from2To3.dart`), not in `shared_preferences`, which STACK.md forbids. An unreadable flag never blocks the app: the home screen opens.

Q9 is answered as built-in: the three templates live in `BuiltInTemplateCatalog`, and their titles and descriptions are ARB keys mapped by template id.

A project created from a template has the template's layers and no clips. `InstantiateTemplate` keeps its rule (no project without usable media for every slot) and stays the path for filling slots, but there is no media import yet, so the home screen could not use it. The empty layers are editable and the slots are filled once import exists. This is the one place where FR-13 is only partly met.

The editor gets an "Add layer" action (video, image or audio, placed in front) through the new `AddLayer` use case, and a hint that importing media comes with the media engine.

## Consequences

- Added: `CreateProject`, `AddLayer`, `ProjectSummary`, `ProjectRepository.summaries()` (three queries, no N+1), `TemplateCatalog.all()`, `lib/features/home/`, `lib/features/onboarding/`, `lib/core/db/tables/app_settings_table.dart`, schema dump v3 and its migration test.
- Removed: `firstProjectId` and `editorProjectProvider`; the editor no longer picks a project by itself.
- Not decided and not enforced: the layer limit (Q5), so `AddLayer` has none. Deleting or renaming a project is not built.
- Clips still cannot be added from the UI: `AddClipToLayer` exists in the domain but import (Q12, Rust/FFI) is out.
