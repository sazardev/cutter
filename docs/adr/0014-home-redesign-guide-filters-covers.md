# 0014. Home redesign: guided new project, search and filters, pins, covers, delete

## Status

Accepted · 2026-10-21

## Context

The home screen listed projects with no way to find one among many, started a project with one tap and no choices, and showed every project as the same icon. The user asked for a roomier layout on desktop and a nicer one on phones, search, filters, sort, pins, paging, a guided new project, deleting a project, and a preview of the first frame of each project.

## Decision

- **List.** `applyProjectQuery` (domain, pure) searches by name and filters by kind (all, saved, empty), last edit (today, 7 or 30 days) and length (under 30 s, to 2 min, over); `ProjectSort` has five orders. The search field is centered, follows the corner style of the buttons, and suggests project names as you type. A button at its right opens a full-screen modal with sort and filters; applied filters show as removable chips. Pinned projects have their own section, always in full; the rest is paged by 12 with "Show more". Pins and the sort are stored in `app_settings` (`home.*`), the query is not persisted. Pins of deleted projects are pruned.
- **Cover.** `ProjectSummary` gains `coverUri` and `coverMs`: the first picture or video clip (earliest start, then lowest layer) and its in point, derived in `EditorDao.summaries()` from rows already read (no schema change). `projectCoverProvider` asks the engine for that frame at 240 px; a missing file keeps the plain poster.
- **New project.** `NewProjectPage` is a four-step guide (start from blank or a template, screen shape, frame rate, name) with "Create now with defaults" on the first three. `CreateProject` takes an optional `Canvas`. Templates on the home screen only appear while there are no projects.
- **Rename, archive, trash.** The card menu renames a project (`RenameProject`), archives it (kept, out of the main list) or moves it to the trash, where it waits 7 days and is then deleted for good when the home screen loads; it can be restored before that. Archived and trash are parts of the library picked in the filter modal (`ProjectScope`). Archived ids and trash dates live in `app_settings` (`home.archived`, `home.trash`), not in new columns, so there is no schema change; a `deleted_at` column can replace this when sync (Q10) needs it. Moving to trash or archiving unpins.
- **Delete.** `ProjectRepository.delete` removes layers, clips and versions and unlinks exports and media-bank rows in one transaction, without relying on foreign key enforcement. It is a hard delete, now only from the trash and by the 7-day purge (the sync outbox waits on Q10), behind a confirmation that says what is lost. No SnackBars (the user asked to remove them all).

## Consequences

- A target duration ("time") in the guide is not stored: `Project` has no such field and adding one changes the schema, which needs approval.
- The cover is the clip's source frame, not the composited frame at 0 s.
- Added: `lib/features/home/{domain,data}`, `project_toolbar.dart`, `project_filters_page.dart`, `project_cover.dart`, `new_project/`, `ProjectRepository.delete`, `EditorDao.deleteProject`.
