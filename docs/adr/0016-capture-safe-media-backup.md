# 0016. Capture, safe media, import limits, relinking and backup

## Status

Accepted · 2026-10-21

## Context

SPEC.md left Q10 (local or network), Q11 and Q12 (what can be imported), Q15 (what "record" covers) and Q16 (autosave) open. The user asked for photos, video and voice to be recorded into the project, for the app not to break when a file moves or the disk fills, and for a copy to exist. The owner approved these choices: capture with `image_picker` and `record`, interrupted recordings kept, import limits that warn instead of block, every file copied into the app, a project backup file, and relinking of missing media.

## Decision

- **Local only (Q10).** No network. The sync engine and outbox in STACK.md stay future work.
- **Every file is kept by the app.** `MediaLibrary.keep` copies each imported or recorded file into the app's media folder. A file the picker left in a cache directory is moved instead (Android picks land there, and a second copy would only waste space). A full disk (`ENOSPC`) becomes `MediaStorageFull`, any other failure `MediaCopyFailed`, and a half-written copy is removed. The original is never touched.
- **Limits warn, never block (Q11, Q12).** Above 4K (more than 3840x2160 pixels), one hour or 4 GB an imported file raises an `ImportNotice`; a file the engine cannot read, one shorter than a clip, and one that could not be copied raise an `ImportIssue` with its reason. `ImportOutcome` carries both and `showImportReport` lists them, so nothing is dropped silently. No SnackBars (the user asked to remove them all): the report is a dialog, shown only when there is something to say.
- **Missing media.** `missingSourcesProvider` checks which clip files no longer exist (on open, after an edit and when the app comes back to the front). Those clips are drawn in the error color with a link-off badge, left out of the engine timeline, the export button is disabled with a reason, and a banner offers "Find file". `RelinkMedia` points every clip that used the file at a new one when its kind matches and it is long enough; trims and places are kept. Otherwise nothing changes and the user is told why.
- **Capture (Q15).** A Capture tool (`lib/features/capture/`): photo and video use the system camera through `image_picker` and are appended to the picture sequence; voice uses `record`, starts at the playhead (optionally playing the timeline along) and lands there as a sound clip. A recording cut short (the app leaves the front, the recorder fails to stop) is kept and the user is told. A capture the system finished while the app was closed is recovered when the panel opens (`retrieveLostData`). A denied microphone or camera explains itself and links to the system settings. Android declares only `RECORD_AUDIO`: declaring `CAMERA` would make the system camera fail until it is granted to Cutter; iOS has the two usage descriptions.
- **Backup.** `writeBackup` writes one `.cutter` file: the magic `CUTTERBK`, the format and the manifest length (two big-endian 32-bit integers), the manifest (the project snapshot and the list of media with their sizes) and then the media bytes in that order. It is written aside and renamed when complete. `readBackup` checks the magic, the format (a newer one is refused with its own message) and that the sizes add up (a truncated file is "damaged"), unpacks into the media folder, gives the project, its layers and its clips new ids so it never clashes with the original, and removes what it unpacked if anything fails. A file that was already missing when the backup was made is not included; the restored clip shows as missing and can be relinked. The home screen has "Back up" in each project's menu (written to the export folder) and a "Restore backup" button.
- **Storage in Settings.** A Storage section shows what Cutter holds (media folder, rendered videos from the export records, cache), a bar of those parts, and the space each project's clips take (files shared with other projects are marked). Clearing the cache only touches the app's own cache folder (never the system temporary folder, which on desktop is shared) and keeps files younger than an hour, since a picked file or a recording may be waiting there. "Unused media" are files in the media folder that no clip of any project uses; deleting them asks first, only ever removes files inside the media folder, and takes them out of the media bank. Music packs have their own size in the Music section and are not counted here.

## Consequences

- Importing copies, so a project costs disk space: a 2 GB video takes 2 GB more unless it came from the cache. There is no pre-check of free space (no plugin for it); the copy simply fails cleanly.
- Capture, backup and restore are tested with fakes and temporary files; the camera screen, the microphone permission prompt, a real interruption and a real full disk need a device.
- A restored project keeps its clips' media only if the backup held them; the backup is not encrypted or compressed.
- Added: `image_picker`, `record`; `lib/features/capture/`, `lib/features/backup/`; `ImportOutcome.issues` and `.notices`; `Clip.copyWith(sourceUri, assetId)`; `ProjectRepository` is unchanged.
