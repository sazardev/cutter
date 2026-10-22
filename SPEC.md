# SPEC.md: Cutter mobile video editor

## Summary
Cutter is a multi-layer video editor for mobile phones and tablets, comparable in ambition to the TikTok editor and the Google Photos editor, with music, audio, microphone and camera recording, video and image layers, adjustments, filters, presets and templates. The UI is Flutter; all editing and media processing runs in a Rust backend reached through FFI. The product promise is unprecedented speed: a sustained 60 FPS with zero tolerance for frame drops, at all times.

## Problem
Creators editing multi-layer video on phones and tablets are forced to choose between simple editors that cannot do multi-layer, audio and effects work, and pro editors that stutter, block the UI and make trimming and scrubbing feel laggy. Existing mobile editors do not hold a stable frame rate while decoding, compositing and applying effects, so the edit itself becomes the bottleneck. Flutter gives a productive cross-device UI layer and Rust gives native-speed media processing on device, so the performance ceiling of current editors is no longer a technical necessity.

## Goals
- G1: Hold 60 FPS in preview playback, timeline scrubbing and timeline manipulation, with zero frames exceeding the 16.67 ms frame budget during a continuous 60-second measured session (see NFR-1).
- G2: Run all decode, composition, effect and timeline mutation work in the Rust engine over FFI, keeping the Flutter UI thread free of media work (see FR-16, NFR-2).
- G3: Ship the full editing surface named in the draft: multi-layer timeline, music, audio, microphone, recording, video, images, adjust, modify, filters, presets, templates, volumes, reverse, cut, split, move (FR-1 to FR-15).
- G4: Make every editing action reachable and comfortable on both phone and tablet form factors, and accessible at all times (FR-17, NFR-5).

## Non-goals
- No desktop or web build: the draft targets mobile and tablet only.
- No social network, feed, or in-app publishing surface: Cutter is an editor, not a sharing platform.
- No server-side rendering or cloud processing: the speed claim rests on the on-device Rust engine.
- No multi-user collaboration or shared project sessions.
- No AI-generated content features: "inteligente" is not specified (see Q3).
- No export/share pipeline in this spec until scope is confirmed (see Q2).

## Users and scenarios
Personas:
- P1 Mobile creator: records and edits short multi-layer videos on a phone, one-handed, in short sessions.
- P2 Tablet editor: builds longer, layered compositions with music, voice-over, images and filters on a larger canvas.

Scenarios:
1. Multi-layer assembly: P1 imports a video and an image, adds a music track, orders layers, trims each clip, plays back at 60 FPS, saves the project.
2. Voice-over recording: P1 plays the timeline, records microphone audio, the new clip lands on an audio layer at the playhead, then P1 sets its volume.
3. Camera capture: P1 records a video clip in-app, it is appended to a video layer, then P1 splits and moves it.
4. Fine cut: P2 splits a clip at the playhead, moves the second half to another layer, reverses it, and scrubs the timeline without stutter.
5. Look and reuse: P2 applies a filter and an adjustment to a clip, saves the look as a preset, then starts a new project from a template.
6. Long session: P2 edits for 30 minutes with continuous preview; the app must remain at 60 FPS and must not lose the project (see Q16).

## Requirements
**FR-1 — Multi-layer timeline.** The system must compose multiple layers of video, image and audio in a single timeline.
- Given a project, when the user adds a video layer, an image layer and an audio layer, then all three render composited in the preview in the layer order shown in the timeline.
- Given N layers where N is within the confirmed limit (see Q5), when the user reorders layers, then the preview reflects the new order within one frame.

**FR-2 — Media import.** The system must import video and image files from device storage into the timeline.
- Given a device media item in a supported format (see Q12), when the user selects it, then a clip referencing it is created on the target layer with its intrinsic duration and dimensions.
- Given an unsupported or corrupt file, when the user selects it, then import fails with a user-visible message and the project is unchanged.

**FR-3 — Music and audio layers.** The system must place music and audio files on audio layers.
- Given an audio file, when the user adds it to an audio layer, then it plays in sync with video layers during preview.
- Given an audio clip on a layer, when the user sets its volume, then the change is audible in the next preview pass and is persisted in the project.

**FR-4 — Microphone recording.** The system must record audio from the device microphone and place it on an audio layer.
- Given microphone permission granted, when the user starts recording during playback, then recording starts, the playhead advances, and stopping creates an audio clip starting at the record-start playhead position.
- Given microphone permission denied, when the user taps record, then no recording starts and the app explains how to grant permission (see Q15).

**FR-5 — Camera video capture.** The system must record video from the device camera and place it on a video layer.
- Given camera permission granted, when the user records, then a video clip of the recorded duration is created on the target video layer.
- Given capture is interrupted (backgrounded, permission revoked, storage full), when the interruption occurs, then the partial recording is discarded or kept per Q15 and the app remains usable.

**FR-6 — Trim (cut).** The system must trim the in and out points of any clip.
- Given a clip, when the user drags its in or out handle, then the preview shows the new boundary frame during the drag and the clip duration updates on release.
- Given a trim that would make duration zero or negative, when released, then the trim is rejected and the previous in/out points are restored.

**FR-7 — Split.** The system must split a clip at the playhead.
- Given a clip spanning the playhead, when the user splits, then two adjacent clips are produced with no gap and total duration preserved.
- Given the playhead outside the clip bounds, when the user splits, then the action is disabled or rejected without modifying the project.

**FR-8 — Move.** The system must move clips in time and across layers.
- Given a clip, when the user drags it, then it changes start time and/or layer, and the preview reflects the new position on release.
- Given a drop position overlapping another clip on the same layer, then the drop is rejected or resolved per Q5 without silently deleting either clip.

**FR-9 — Reverse.** The system must reverse a clip's playback direction.
- Given a video clip, when the user enables reverse, then preview and playback show the clip's frames in reverse order for the clip duration.
- Given reverse is toggled off, then the clip plays forward again with unchanged in/out points.

**FR-10 — Adjust and modify.** The system must expose per-clip adjustment and modification controls on clips and route them through the Rust engine.
- Given a clip, when the user changes an adjustment value, then the preview updates within the next frame and the value is stored on the clip.
- Given the adjustment set is still unspecified (see Q4), then the implemented controls are exactly the confirmed set and no others.

**FR-11 — Filters.** The system must apply visual filters to video and image clips.
- Given a clip, when the user selects a filter, then the preview shows the filtered result at 60 FPS.
- Given a filter is applied, when the user removes it, then the clip renders with original pixels.

**FR-12 — Presets.** The system must save a set of clip settings as a preset and apply it to other clips.
- Given a configured clip, when the user saves a preset, then the preset is listed and persists across app restarts.
- Given a preset, when applied to a compatible clip, then all captured settings are applied and previewed.

**FR-13 — Templates.** The system must create a project from a template.
- Given a template, when the user selects it, then a new project is created with the template's layers and settings and the user can replace its media.
- Given the template's media expectations are unmet (see Q9), then the app states what is missing and does not create a broken project.

**FR-14 — Volume controls.** The system must control volume per clip and per audio layer, including mute.
- Given an audio or video clip with audio, when the user sets clip volume to 0, then that clip is silent in preview while other clips are unaffected.
- Given a layer volume change, then all clips on that layer reflect it, combined with per-clip volume.

**FR-15 — Playback and scrubbing.** The system must play the composited timeline and scrub it at 60 FPS.
- Given a project, when the user presses play, then all layers play in sync with audio at 60 FPS.
- Given the user drags the playhead, then preview frames update during the drag without the UI thread blocking (NFR-2).

**FR-16 — Rust engine over FFI.** The system must perform all media decode, composition, effect application and timeline mutation in the Rust engine, exposed to Flutter through FFI.
- Given any editing action, when it is applied, then the Flutter side sends a command over FFI and receives state or frames, and performs no media decoding or pixel processing itself.
- Given the Rust engine returns an error, then the Flutter UI surfaces it and the project state stays consistent.

**FR-17 — Accessibility and comfort.** The system must keep all editing controls reachable and usable on phone and tablet, with system accessibility services supported.
- Given a screen reader is enabled, when the user navigates the timeline and controls, then every control exposes a label and the timeline is operable.
- Given a phone or tablet form factor, then every primary editing action is reachable without a hardware keyboard or mouse (see Q7).

**FR-18 — Text layers.** The system must place text over the video on layers of its own, as many as the user wants, each with its own time, position and look.
- Given the Add layer button, then a menu asks which kind of layer (video, image, audio or text) before anything opens; choosing Text adds a text and opens its tool, and the left tool bar has no Text entry.
- Given the text tool, when the user adds a text, then it appears at the playhead for 3 seconds, centred, selected and ready to type over; a text that starts while another is showing goes on a layer of its own and is nudged down so neither hides the other, and texts one after the other share a layer.
- Given a selected text, when the user types or changes its font, size, colour, outline, shadow, background, letter spacing, alignment or entrance, then the preview shows it as it changes and one pause saves it as one step of undo.
- Given a text in the preview, when the user drags, pinches or turns it, then it moves, scales and rotates like any picture; a double tap opens the text tool.
- Given a text clip on the timeline, then it can be moved, trimmed to either side, split, duplicated and deleted like any clip, and layers of text can be reordered among the others.
- Given a text, when the project is exported, then the video shows the same words, font and look as the preview, drawn by the engine from the fonts bundled with the app.

## Non-functional requirements
- NFR-1 Performance: preview playback, scrubbing, trimming and dragging must sustain 60 FPS with zero dropped frames; every frame completes within 16.67 ms, verified over a continuous 60-second session per interaction on target devices. Any frame over budget is a defect, not a warning.
- NFR-2 UI responsiveness: no Flutter UI-thread operation may block longer than one frame budget; all Rust engine work runs off the UI thread.
- NFR-3 Engine latency: an edit command issued over FFI must be reflected in the preview state within one frame (16.67 ms) after the engine acknowledges it.
- NFR-4 Platform scope: the app must run on mobile phones and tablets; the supported OS list and minimum device tier for the 60 FPS guarantee are pending (see Q1, Q6).
- NFR-5 Permissions and privacy: camera and microphone access must be requested at time of use, denial must never crash or block the editor, and recorded media must remain usable per the storage decision in Q10.
- NFR-6 Localization: all user-facing strings must be externalized so the UI language can be set without code changes; the supported language list is pending (see Q14).
- NFR-7 Robustness: project state must survive app backgrounding and process kill without corruption (persistence policy pending, see Q16).

## Data
| Entity | Fields | Relations |
|---|---|---|
| Project | id, name, created_at, updated_at, canvas width/height/fps (pending Q5), layer order | has many Layers; may originate from a Template |
| Layer | id, project_id, type (video \| image \| audio \| text), index, volume, muted | has many Clips; belongs to Project |
| Clip | id, layer_id, source_uri, media_type, start_time, duration, in_point, out_point, reversed, volume, filter_id, adjustments | belongs to Layer; references Filter and Adjustment set |
| MediaAsset | id, uri, media_type, duration, width, height, codec, audio_present | referenced by Clips; source for imports and recordings |
| Recording | id, kind (microphone \| camera), uri, duration, created_at | produces a MediaAsset and a Clip |
| Filter | id, name, parameters | applied to Clips |
| Preset | id, name, captured settings (filter_id, adjustments, volume), created_at | applied to Clips |
| Template | id, name, layer/clip layout, expected media slots | instantiates a Project |
| Adjustment | key, value, range | stored per Clip |

All times are in a single integer timebase for the project; the unit is pending (see Q5).

## Interfaces
Screens (Flutter):
1. Editor: timeline with layers, playhead, preview canvas; inputs = gestures and toolbar actions; outputs = FFI commands, preview frames.
2. Media picker: inputs = media type filter; outputs = selected MediaAsset for import.
3. Record: inputs = microphone or camera mode, start/stop; outputs = Recording, new Clip.
4. Clip inspector: inputs = trim, split, move, reverse, volume, filter, adjust controls; outputs = updated Clip.
5. Filters and adjustments browser: inputs = selection; outputs = Filter or Adjustment values applied to the selected Clip.
6. Presets: inputs = save/apply; outputs = Preset records.
7. Templates: inputs = template selection and media slot filling; outputs = new Project.

Rust engine FFI surface (names indicative, semantics binding):
| Command | Input | Output |
|---|---|---|
| `project_open` / `project_save` | project id or serialized project | project handle / success |
| `media_import` | uri, media_type | MediaAsset metadata |
| `layer_add` / `layer_reorder` | project handle, layer spec | updated layer list |
| `clip_add` / `clip_remove` | layer id, asset id, start_time | clip id |
| `clip_trim` | clip id, in_point, out_point | updated clip duration |
| `clip_split` | clip id, at_time | two clip ids |
| `clip_move` | clip id, target layer, start_time | updated clip |
| `clip_set_reverse` | clip id, enabled | updated clip |
| `clip_set_volume` / `layer_set_volume` | id, volume, muted | updated state |
| `clip_set_filter` / `clip_set_adjustments` | clip id, filter id or adjustment map | updated clip |
| `preset_save` / `preset_apply` | clip id, name / preset id | preset record / updated clip |
| `template_instantiate` | template id, media slot map | new project handle |
| `preview_frame` / `playback_start` / `playback_stop` | project handle, time or range | frame buffer / status |
Events from engine to UI: frame ready, playback position, engine error, permission or decode failure.

## Edge cases
- Camera or microphone permission denied: record action is disabled with an explanation; editor stays fully usable.
- Source file unsupported or corrupt: import rejected with a message; project unchanged.
- Trim to zero or negative duration: rejected; previous in/out restored.
- Split at or outside clip boundaries: rejected without mutating the project.
- Move onto an occupied range on the same layer: rejected or resolved per Q5; no silent deletion.
- Reverse on a clip whose source cannot be decoded backwards: fall back to a defined behavior pending Q13, never a blank or frozen preview.
- Audio and video drift during playback: playback must resync at the next frame, not accumulate drift.
- App backgrounded during recording or playback: recording stops per Q15; playback pauses; project state remains valid.
- Device storage full or memory pressure: edit or record fails with a message; no partially written project.
- Very large or long media: behavior pending the limits in Q11.
- Device below the performance tier: the 60 FPS guarantee scope is undefined (Q6); the app must degrade without crashing.
- Screen rotation and phone/tablet layout change mid-edit: timeline state and playhead position are preserved.
- Undo of any destructive action: not defined in the draft (see Q8).

## Open questions
- Q1: Which operating systems and minimum versions must Cutter support (Android, iOS, both)?
- Q2: Does Cutter export finished videos, and if so in which formats, resolutions and bitrates? Export is not described in the draft.
- Q3: What does "inteligente" mean concretely — automatic cuts, beat detection, auto-captions, smart presets, or something else? No feature is specified.
- Q4: "Ajustar, modificar" — which exact adjustable parameters per clip (brightness, contrast, saturation, crop, scale, rotation, speed, others)?
- Q5: What are the hard limits: maximum layers per project, maximum clips, project canvas resolution and frame rate, timeline timebase unit, and overlap rule for clips on one layer?
- Q6: Which device tier must hit 60 FPS with zero dropped frames, and what is acceptable on lower-tier devices?
- Q7: Does "accesible en todo momento" mean accessibility (screen readers, contrast, large text) or simply always-available editing controls? Which accessibility standard and level apply?
- Q8: Is undo/redo required, and what is its depth?
- Q9: Where do presets and templates come from (built-in, user-created, downloadable), and what is their file format and media-slot contract?
- Q10: Is all media and project data strictly local, or is any network storage or sync expected?
  - **Answered (ADR 0016):** local only for now. Nothing leaves the device; the sync engine and outbox in STACK.md stay future work until a network feature is chosen. Every imported or recorded file is copied into the app's own storage, and a project can be backed up to one `.cutter` file and restored from it.
- Q11: What are the maximum import size, duration and resolution, and the supported codecs/containers?
  - **Answered (ADR 0016):** no hard limits. A file above 4K, one hour or 4 GB is imported with a warning; only a file the engine cannot read, or one shorter than a clip, is left out, with the reason. Containers and codecs are whatever the engine plays; the extensions offered are in `media_formats.dart`.
- Q12: Are image formats limited to stills, and which ones (JPEG, PNG, HEIC, WebP)?
  - **Answered (ADR 0016):** stills only: JPEG, PNG, WebP, GIF (first frame), BMP, TIFF, HEIC/HEIF and AVIF, as far as the engine reads them; one it cannot read is reported like any unreadable file.
- Q13: Does reverse apply to audio clips too, and what is the behavior for clips whose audio cannot be reversed?
- Q14: Which UI languages must ship, and is Spanish the default?
- Q15: Does "grabar" cover microphone voice-over, camera video capture, or both? On interruption, is a partial recording kept or discarded?
  - **Answered (ADR 0016):** both, plus photos. Voice is recorded inside the editor and lands on an audio layer at the playhead where recording began; photos and videos use the system camera and are appended to the picture sequence. An interrupted recording is kept, with a notice. A denied permission records nothing, explains why and links to the system settings. On Android only `RECORD_AUDIO` is declared, so the system camera works without a camera permission for Cutter.
- Q16: Is there autosave, and what is the persistence format and recovery behavior after a crash?
  - **Answered (ADR 0013):** every edit is written to the local database at once, and restore points are saved on their own (when a project first opens, every 10 minutes after an edit, and before a restore). After a crash the project opens as last written.

## Milestones
1. M1 — Runtime skeleton: Flutter app shell plus Rust engine over FFI; open one imported video, render preview frames from Rust. Exit: preview of a single clip at 60 FPS, zero frames over 16.67 ms in a 60-second session.
2. M2 — Single-track editing: trim, split, move within one video layer, with playhead scrubbing. Exit: all three actions reflected in preview within one frame; no UI-thread stalls.
3. M3 — Multi-layer timeline: video, image and audio layers, layer ordering, music import, per-clip and per-layer volume and mute. Exit: composited playback of 3 layers in sync at 60 FPS.
4. M4 — Recording: microphone voice-over and camera capture into the timeline, with permission handling. Exit: recorded clip lands at the playhead and plays back in sync; denial path is clean.
5. M5 — Reverse: reversed playback for video clips. Exit: reverse toggles correctly with unchanged in/out points (Q13 resolved before build).
6. M6 — Adjust and filters: per-clip adjustments and filters in the Rust engine. Exit: filter and adjustment changes preview within one frame at 60 FPS (Q4 resolved before build).
7. M7 — Presets: save and apply clip setting sets, persisted across restarts.
8. M8 — Templates: instantiate projects from templates with media slot filling.
9. M9 — Hardening: accessibility pass, localization externalization, background/kill robustness, and the full 60 FPS verification matrix across phone and tablet (Q1, Q6, Q7, Q14, Q16 resolved before build).
