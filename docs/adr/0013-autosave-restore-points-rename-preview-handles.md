# 0013. Restore points, rename in place, handles on the preview, and a timeline that starts at the left

## Status

Accepted · 2026-10-21

## Context

The user asked that a project be saved from the moment it exists so that nothing is lost, that versions only serve to go back to a saved point, and that the name can be changed by tapping it. They also asked that tapping the preview stop playing it (only the play button plays), that pictures and videos be movable, rotatable and scalable by their handles, and that the timeline start at the left instead of after a large gap.

## Decision

**Everything is saved at once.** Creating a project and every edit already wrote to the database in one step. The Draft/Saved distinction suggested otherwise, so it is gone: the top bar says "Saved", the home list no longer shows a status, and `ProjectSummary.isDraft` and `EditorUiState.savedVersion` are removed. The `saved_at_ms` column stays (no schema change) and holds when the last restore point was saved.

**Versions are restore points.** The user still saves them by hand. The editor now also saves one by itself:

- the first time a project opens (named "Start of the project");
- once `autoCheckpointInterval` (10 minutes) has passed since the last point, checked after each accepted edit;
- just before a restore, so the state that is replaced can be brought back even after the editor closes.

The names come from the screen through `CheckpointLabels`, so they follow the language. Without labels (tests that do not pass them) nothing is saved automatically. There is no flag marking a point as automatic, because that needs a schema change; they are told apart by name.

**Rename.** `RenameProject` trims the name, rejects a blank one and cuts it to 80 characters. The title in the top bar becomes a field in place (no dialog). Enter or leaving the field keeps the name, Esc cancels. It goes through the same path as any edit, so it can be undone, and it refreshes the home list.

**Preview.** A tap never plays or pauses; the play button, Space and the transport do. A tap on a picture selects it and a tap on empty canvas clears the selection. A drag on a picture selects and moves it in one motion (the selected one wins when it is under the finger). The corner handles scale it, the handle above it turns it, and with two fingers a pinch scales and a twist turns it. Handles are looked for at the point where the finger went down, because a drag is only recognised after the finger has slid, and are kept inside the canvas so a picture that fills it still has reachable handles.

**Timeline.** The playhead is no longer fixed in the middle with half a screen of empty space before time zero. Time zero sits at the left, next to the track headers. The playhead moves along it, and while playing the view follows once the playhead reaches the middle. Scrolling only looks around; a tap or a drag on the ruler places the playhead.

**No snackbars.** Changes simply apply: the app shows no snackbar anywhere, the theme has no snackbar style, and a rejected edit or an unusable file is left out silently. Undo stays in the top bar. `failure_message.dart` and its strings were removed with them.

**Project settings tool.** A tool in the editor holds the project's name, a restore point on demand, a folder of its own for its exported videos (kept in `app_settings` under `project.<id>.export_dir`, so no schema change; the Settings folder is the default), a shortcut to the format, and deleting the project. Deleting asks first, inline in the panel, and cannot be undone; it removes the project's layers, clips and versions, and the exported videos stay. Where the system has no folder picker the in-app browser picks the folder.

**Layers follow their content.** A layer left without clips is removed after the edit and stored, and when a project opens (a project with no clip at all keeps its layers, as a template waiting for media). A mini button under the layer headers of the timeline picks media and puts it on a new layer of its kind at the playhead (a picture makes a picture layer, sound a sound layer).

**Layer order by drag.** A long press on a layer's header lifts it (haptic, tinted header and row); dragging up or down swaps it with each layer whose middle it crosses, live, and letting go stores the order through `ReorderLayers` (one undo step). Screen readers get "Move layer up/down" actions. The mute button's tooltip shows on hover only, since a touch tooltip also reacts to a long press and would take the gesture.

**Share after export (`share_plus`, approved by the user).** The finished video offers a Share button that opens the system share sheet, a row of platform shortcuts (WhatsApp, Instagram, TikTok, YouTube, Facebook, Telegram, X, Snapchat), and Watch, Open folder and Copy path. The shortcuts all open the same system sheet: `share_plus` cannot aim at one app, so the user picks the app there, and the icons are stand-ins because the icon set has no brand logos. On Linux the plugin shares no files, so there the share options are left out and only the other actions show. A Share section in Settings turns each part on or off: the share options, opening the sheet on its own when the export finishes, each platform, and each action; they are kept in `app_settings` under `share.*`. The product still publishes nothing itself.

**Resizable divider.** `EditorSplit` replaces the fixed 3:2 split between the preview and the timeline, in every arrangement (below, above, beside). A divider with a small pill at its centre, half hidden until touched, can be dragged to give one side more room, and a tap on the pill goes from balanced to the preview filling the space, to the timeline filling it, and back. Near either edge the drag snaps to that focus. The transport bar stays visible next to the preview (inside the preview side when the timeline is beside it, where focusing the timeline hides it). A squeezed pane is laid out at a minimum size and clipped, so nothing overflows and its state survives. The share is kept in `app_settings` (`editor.preview_share`).

**Short bar for a selected clip.** A tap on a clip selects it and shows only a short pill with Edit, Duplicate, Split, Delete and More (floating over the timeline on wide windows, in the bottom bar on phones). The full options (the right panel, or the long tool bar with framing, volume, filters, adjust and reverse) open with a double tap on the clip or in the preview, or with More; `clipDetailsProvider` holds the id of the clip they are open for, so selecting another clip closes them. The first tap is acted on at once and a second tap within 320 ms only upgrades it, so a single tap never waits. Esc closes the full options first, and the panel's close button goes back to the short bar.

## Consequences

- A restore never loses the current state, and a long session leaves a point at most about ten minutes behind.
- Restore points accumulate without a limit. Pruning needs a way to tell automatic points from manual ones, which is a schema change to ask about.
- The periodic checkpoint has no test: it depends on the clock and the controller has no clock to inject.
- Scrolling the timeline with the finger no longer moves the playhead. Anyone used to scrubbing by scrolling now scrubs on the ruler.
