# 0019. Image effects, clip animations and background removal

## Status

Accepted · 2026-10-21

## Context

The user asked for more filters and image options (blur, remove background), animations and effects on video, and a way to draw. Filters were four colour matrices; there were no spatial effects, no per-clip animation and no background removal.

## Decision

- **More filters.** Seven new colour matrices (sepia, noir, vivid, fade, cinema, sunset, invert) next to the four old ones. A filter is still an id the engine maps to a matrix, so no schema change. `FILTER_IDS` (Rust) and `filterIds` (Dart) are compared by a Dart test.
- **Spatial effects.** Blur, vignette, grain, pixelate and sharpen, each 0 to 1, in `render/fx.rs`. They are stored as keys of the clip's `adjustments` map (no schema change) and reach the engine as new `TimelineClip` fields. They run on a copy of the clip's decoded frame, before it is drawn. Grain is seeded by the frame time, so scrubbing and export agree.
- **Clip animations.** Each clip has an entrance and an exit (fade, four slides, zoom in, zoom out, spin, pop), each 0.1 to 3 s, in `render/animation.rs`, applied to the clip's placement in the compositor. The exit is the entrance played backwards; spans that would overlap on a short clip share it. Schema v8 adds `anim_in`, `anim_in_ms`, `anim_out`, `anim_out_ms` to `editor_clips`. `SetClipAnimation` skips audio and text (a text has its own animation).
- **Background removal, images only.** `render/background.rs` runs U²-Net-P (4.6 MB, Apache-2.0, bundled in `rust/assets/models/`) with `tract-onnx`, a pure Rust ONNX engine, and writes a PNG with the mask as alpha (`png` crate). The picture is shrunk to 2048 px on its long side first. `EditorController.removeBackground` writes the cutout into the media library (`cutouts/`) and `ReplaceClipPicture` points the clip at it, keeping its place, framing and look; undo restores the original, which is never touched.
- **Why `tract` and not ONNX Runtime (`ort`).** `ort` was tried first and needs to download a prebuilt runtime from a CDN, which this build environment blocks (HTTP 403). `tract` downloads nothing, links nothing native and crosses to Android and iOS with the rest of the crate, which matters because the Android build is still open. Its cost is speed: it is a CPU engine.
- **Drawing.** A drawing is a clip of kind image whose picture is a transparent PNG rendered from its strokes, so it reuses transform, opacity, fades, filters and animations like any picture. `ClipDrawing` (strokes of colour, thickness and points, as fractions of the canvas) is kept in schema v9 (`editor_clips.drawing_json`) so the drawing can be edited again. `DrawingPage` is a full-screen screen with a palette, thickness, an eraser and undo; `paintDrawing` is shared by the screen and the PNG (a `Canvas` in Flutter: this is rendering of a picture, once, not per-frame media work). `AddDrawingClip` puts the clip on the first free image layer or a new one in front; `SetClipDrawing` swaps strokes and PNG and keeps the clip's place and look. It is reached from Add layer (Drawing) and by editing a drawing clip. The rendered PNGs live in the media library under `drawings/`.

## Consequences

- New dependencies in `rust/Cargo.toml`: `tract-onnx` and `png`. `tract` roughly doubles a cold build of the crate.
- The engine library grows by the 4.6 MB model.
- Not measured: the cost of blur, sharpen and grain on a 60 fps preview at 1080p, nor a cutout on a phone. Effects copy and process the clip's frame every frame, so a heavy stack of them on a large clip may break the frame budget (NFR-1); it needs a benchmark on a device before more effects are added.
- Old drawing PNGs stay in `drawings/` after an edit or an undo; the storage cleaner treats them like other unused media.
- Verified with tests only: the network keeps a bright subject on a dark field, the PNG keeps its transparency, and the editor swaps and undoes the picture. It was not run on a real photo or a device.
