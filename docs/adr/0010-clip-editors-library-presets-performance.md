# 0010. Clip editors, video library, export presets, and performance budgets

## Status

Accepted · 2026-10-21

## Context

The user asked for heavy real use to hold up: many cuts, several videos, images and sound tracks, without stalling the preview or exhausting CPU and memory. The other requests:

- smart automatic adjustments;
- isolated editors for a video, an image or a sound;
- a section with the rendered videos;
- export presets by platform and quality.

They approved schema version 5 (crop, sound fades, speed, exports library) and platform and quality presets.

## Decision

**Performance, measured first.** A stress benchmark with real material (eight cuts of a 1080p video, a picture-in-picture video, four images; `cargo test --release bench_ -- --ignored`) and the profile build of the app under WSLg drove these changes:

- **Per-clip decoders with prefetch.** The source has a keyframe every ~8 s, so every cut stalled for up to 147 ms. Each clip now has its own decoder, opened and positioned on a worker 1.5 s before the clip starts. At most four stay open, and decoders idle for 3 s close.
- **Decode budgets by use.** One thread for thumbnails and analysis, without the deblocking filter. Two for the preview. Four for export.
- **Composition in bands of rows.** Two threads in the preview, up to four in export.
- **Adaptive preview quality.** While playing, the preview scales down to 50% when frames approach their budget and climbs back when there is room. Paused frames and exports are always full size.
- **Thumbnails within a tolerance.** A thumbnail decodes forward from the keyframe only as far as its tile step needs (at most 1.5 s), and readers are cached between requests.
- **Clip painters draw only the visible window plus a screen of margin.** Before, `getLocalClipBounds()` inside a `RepaintBoundary` returned the whole clip: a 5-minute clip requested hundreds of thumbnails, overran the cache and requested them again forever (200% CPU while paused).
- **Results:**
  - preview at real-time pacing: 4.2 ms per frame on average, 1 frame over 33 ms in 713;
  - export: 2–2.6× real time at 1080x1920 with three layers, 4.2× at 720p;
  - app paused: 0% CPU (was 200%);
  - app playing: ~250%, of which ~150% is llvmpipe (software OpenGL in WSL, which a GPU takes on a device).

**Two AOT-only defects fixed.**

- A segfault in profile and release builds (`TimelineViewState._trackRow`, found with `--split-debug-info` and `addr2line`). It came from a nullable promoted through a separate `final bool`, and the same pattern in the preview. Both now use plain values.
- A trim drag that moved 3.6 times further than the pointer. The handles now follow the pointer's absolute position on the bar and stop at the neighbouring clips.

**Schema 5.** `editor_clips` gains a crop (fractions cut from each edge), a speed (0.25×–4×) and sound fades. `editor_exports` keeps every rendered video and reconciles files deleted outside the app.

Speed changes the clip's timeline length. Split, trim, the timeline geometry and the engine all respect it. Sound at another speed is muted until pitch-correct stretching exists. The minimum clip length is now one frame (33 ms), so short sound effects import; a file too short or unreadable is reported by name and never takes the rest of an import down.

**Clip editors.** "Edit" on a clip opens a full page with the preview isolated to that clip from zero (`PlaybackController.isolate`). It has a trim bar over a window of its source (the clip plus its own length, at least 5 s, on each side) and tabs that fit its kind:

- video: speed, framing, crop, adjust, filters, volume, fades, reverse;
- image: duration, framing, crop, adjust, filters;
- audio: volume, fades.

Every change is an ordinary edit: saved at once, undoable. Done returns to the same moment of the clip in the project.

**Automatic adjustments.** `suggest_adjustments` (Rust) measures luma, spread and saturation on five frames and returns gentle corrections (at most ±0.2 brightness, +0.25 contrast, +0.2 saturation). They are applied as one undoable edit. The first picture imported into an empty project also gives it its shape (16:9, 1:1, 4:5 or 9:16), with Undo in the message.

**Export presets.** `ExportPlan` picks size, frame rate, bitrate, audio bitrate and encoder effort from a platform (this project, TikTok/Reels/Shorts, YouTube, Instagram feed, WhatsApp light) and a quality (draft 720p veryfast, standard 1080p, high 1080p medium, 4K). It shows the estimated size (47 MB estimated against 48.1 MB measured for 5 min at 720p) and warns when the shape is reframed.

**Your videos.** The home screen lists rendered videos with a poster, duration, size and resolution. A viewer plays them with the engine and offers "edit in a new project", copy path, and delete (a second tap confirms, without a dialog).

## Consequences

- 242 Flutter tests and 37 Rust tests; the two benchmarks are ignored by default.
- Double-tap on a clip was removed: it delayed every single tap by 300 ms. The clip editors open from Edit.
- The engine logs in UTC and the edit log now does too, so both read on one clock.
- Not yet: pitch-correct speed for sound, GPU composition, measurements on a real Android device.
