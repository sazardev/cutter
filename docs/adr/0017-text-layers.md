# 0017. Text layers

## Status

Accepted · 2026-10-21

## Context

The editor had layers of video, images and sound. The user asked for text over the video that is easy to add, type, move, scale, rotate, restyle (font, size, effects), order, chain in time and repeat as often as wanted, without costing frames. The owner chose: the Rust engine draws the text, fonts ship inside the app, and text gets its own layer kind with a schema change.

## Decision

- **The engine draws text.** `render/text.rs` lays out the words with `ab_glyph` (the only new crate) and draws one RGBA picture per look: letters, outline (a round dilation), shadow (offset and blurred), a rounded background and bold or italic faked when the family has no such file. The compositor caches those pictures by look and canvas height (48 at most), so moving, scaling, turning, fading and the entrances only place a cached picture: no text is drawn again while a text moves. The picture goes through the same placement, `copy` or `sample`, and alpha blending as an image.
- **Size in canvas terms.** A text's font size is a fraction of the canvas height, the picture is drawn at the preview's own height, and a clip's scale applies on top at 1:1 instead of fitting the canvas. Line breaks are the user's: nothing wraps, so the size of a text never depends on the canvas width.
- **The editor knows the box without drawing.** `measure_text` (a sync API) answers the size of a text at a reference canvas height of 1000 px; the controller stores it as the clip's `sourceWidth` and `sourceHeight`, so selection frames, handles and hit tests (`placementOf`) work as for any picture, in the same units.
- **Fonts.** Nine families, ids `sans`, `serif`, `mono` (Liberation, with bold and italic files), `anton`, `bebas`, `bangers`, `lobster`, `pacifico` and `marker` (one file each), all under the SIL OFL (or Apache for Permanent Marker). The files live once, in `rust/assets/fonts/`; the engine embeds them with `include_bytes!` and the pubspec declares the same files for the panel's chips, so the preview, the panel and the export agree. An unknown id draws as `sans`.
- **Layers and clips.** `MediaKind.text` and `EngineMediaKind.text`; a text layer holds `Clip`s with a `ClipText` (words and look) and no file. Several texts of a layer may overlap in the engine, but the domain keeps the rule of one clip at a time per layer: `AddTextClip` puts a text on the first text layer where its time is free, or on a new one in front, nudged down by a step so overlapping texts stay readable. A text clip sits in the middle of a 40-minute imaginary source (`textSourceSpanMs`) so the existing trim handles stretch it either way and split, move, duplicate and delete need no special case.
- **Entrances.** `ClipText.animation` (`none`, `fade`, `pop`, `slideUp`) plays over the first and last third of the clip, at most 350 ms.
- **Editing.** The Text tool adds a text and styles the selected one; changes preview through `PlaybackController.previewText` and are saved on release or after a 350 ms typing pause. Edits of one text within 1.5 s are one step of undo.
- **Adding and the panels.** The Add layer button opens a sheet (`add_layer_menu.dart`) that lists Video, Image, Audio and Text; the first three open the picker for that kind and put the files on a new layer in front, Text adds a text at the playhead and opens the text tool. Text is not on the tool bar. The clip tool panels (framing, volume, filters, effects, animations, adjustments, text) were redone as lists of collapsible sections (`tools/panel_kit.dart`: `ToolSection`, `SliderTile`, `OptionTile`): one choice or one slider per line at full width, the current value in the header of a folded section, nothing in a row beside a label.
- **Schema v7.** `editor_clips.text_json` (nullable JSON of `ClipText`; a missing field takes its default, so later looks do not break stored projects) and `editor_layers.kind` accepts `text` (the CHECK is rebuilt with `TableMigration`). The media bank keeps its own list of kinds. Saved versions and backups carry the text in snapshot format 3; older snapshots still read.

## Consequences

- The app grows by the fonts (about 5 MB with the nine families) and the engine by `ab_glyph`.
- A text is not wrapped: a long line can run off the canvas until the user adds a break or shrinks it.
- Outline and shadow are drawn per look, not per frame; a very large text on a high-resolution export is drawn once at the export height, so memory scales with the text's picture.
- Text has no sound: the mixer skips text layers; the layer header shows a text icon instead of a mute button.
- Not covered: per-word styling, curved or animated-per-letter text, and fonts the user installs.
