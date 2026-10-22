//! Draws a text clip's words into an RGBA picture: font, size, colour,
//! outline, shadow and background. The picture is made once per look of the
//! text and cached by the compositor; moving, scaling and turning it is done
//! by the compositor like for any other picture.

use ab_glyph::{point, Font, FontRef, GlyphId, PxScale, ScaleFont};

use crate::api::types::{TextAlign, TextSpec};
use crate::media::video::RgbaFrame;

/// A font family: the files for each weight and slant it ships. A missing
/// one is made from the regular file.
struct Family {
    id: &'static str,
    regular: &'static [u8],
    bold: Option<&'static [u8]>,
    italic: Option<&'static [u8]>,
    bold_italic: Option<&'static [u8]>,
}

macro_rules! font {
    ($file:literal) => {
        include_bytes!(concat!("../../assets/fonts/", $file))
    };
}

/// Every family the editor offers, by the id the text carries (the editor
/// lists the same ids). The first is the fallback for an unknown id.
const FAMILIES: &[Family] = &[
    Family {
        id: "sans",
        regular: font!("LiberationSans-Regular.ttf"),
        bold: Some(font!("LiberationSans-Bold.ttf")),
        italic: Some(font!("LiberationSans-Italic.ttf")),
        bold_italic: Some(font!("LiberationSans-BoldItalic.ttf")),
    },
    Family {
        id: "serif",
        regular: font!("LiberationSerif-Regular.ttf"),
        bold: Some(font!("LiberationSerif-Bold.ttf")),
        italic: Some(font!("LiberationSerif-Italic.ttf")),
        bold_italic: Some(font!("LiberationSerif-BoldItalic.ttf")),
    },
    Family {
        id: "mono",
        regular: font!("LiberationMono-Regular.ttf"),
        bold: Some(font!("LiberationMono-Bold.ttf")),
        italic: None,
        bold_italic: None,
    },
    Family {
        id: "anton",
        regular: font!("Anton-Regular.ttf"),
        bold: None,
        italic: None,
        bold_italic: None,
    },
    Family {
        id: "bebas",
        regular: font!("BebasNeue-Regular.ttf"),
        bold: None,
        italic: None,
        bold_italic: None,
    },
    Family {
        id: "bangers",
        regular: font!("Bangers-Regular.ttf"),
        bold: None,
        italic: None,
        bold_italic: None,
    },
    Family {
        id: "lobster",
        regular: font!("Lobster-Regular.ttf"),
        bold: None,
        italic: None,
        bold_italic: None,
    },
    Family {
        id: "pacifico",
        regular: font!("Pacifico-Regular.ttf"),
        bold: None,
        italic: None,
        bold_italic: None,
    },
    Family {
        id: "marker",
        regular: font!("PermanentMarker-Regular.ttf"),
        bold: None,
        italic: None,
        bold_italic: None,
    },
];

/// How far a slanted glyph leans: horizontal shift per unit of height.
const SLANT: f32 = 0.2;

/// Line height as a multiple of the font's own height.
const LINE_SPACING: f32 = 1.12;

/// The font to draw with, and what has to be faked on top of it.
struct Face {
    font: FontRef<'static>,
    fake_bold: bool,
    fake_italic: bool,
}

fn face_of(spec: &TextSpec) -> Face {
    let family = FAMILIES
        .iter()
        .find(|f| f.id == spec.font)
        .unwrap_or(&FAMILIES[0]);
    let (bytes, fake_bold, fake_italic) = match (spec.bold, spec.italic) {
        (true, true) => match (family.bold_italic, family.bold, family.italic) {
            (Some(b), _, _) => (b, false, false),
            (None, Some(b), _) => (b, false, true),
            (None, None, Some(i)) => (i, true, false),
            (None, None, None) => (family.regular, true, true),
        },
        (true, false) => match family.bold {
            Some(b) => (b, false, false),
            None => (family.regular, true, false),
        },
        (false, true) => match family.italic {
            Some(i) => (i, false, false),
            None => (family.regular, false, true),
        },
        (false, false) => (family.regular, false, false),
    };
    Face {
        // The files are compiled in, so they parse.
        font: FontRef::try_from_slice(bytes).expect("bundled font parses"),
        fake_bold,
        fake_italic,
    }
}

/// One glyph placed on a line: its id and the x of its origin.
struct Placed {
    id: GlyphId,
    x: f32,
}

/// A line of text laid out: its glyphs and width.
struct Line {
    glyphs: Vec<Placed>,
    width: f32,
}

fn layout_lines(face: &Face, scale: PxScale, spacing: f32, content: &str) -> Vec<Line> {
    let scaled = face.font.as_scaled(scale);
    content
        .split('\n')
        .map(|text| {
            let mut glyphs = Vec::new();
            let mut x = 0.0f32;
            let mut previous: Option<GlyphId> = None;
            for ch in text.chars().filter(|c| !c.is_control()) {
                let id = face.font.glyph_id(ch);
                if let Some(prev) = previous {
                    x += scaled.kern(prev, id);
                }
                glyphs.push(Placed { id, x });
                x += scaled.h_advance(id) + spacing;
                previous = Some(id);
            }
            // The spacing after the last glyph is not part of the line.
            let width = if glyphs.is_empty() {
                0.0
            } else {
                (x - spacing).max(0.0)
            };
            Line { glyphs, width }
        })
        .collect()
}

/// The font size in pixels for [spec] on a canvas [canvas_height] pixels
/// tall.
fn pixel_size(spec: &TextSpec, canvas_height: u32) -> f32 {
    (spec.size.clamp(0.01, 1.0) * canvas_height as f32).max(4.0)
}

/// Pixels of padding around the glyphs: room for the outline, the shadow and
/// the background's margin.
struct Margins {
    stroke: i32,
    shadow_dx: i32,
    shadow_blur: i32,
    pad: i32,
}

fn margins_of(spec: &TextSpec, px: f32) -> Margins {
    let stroke = (spec.stroke_width.clamp(0.0, 0.5) * px).round() as i32;
    let shadow = spec.shadow.clamp(0.0, 1.0);
    let shadow_dx = (shadow * px * 0.08).round() as i32;
    let shadow_blur = (shadow * px * 0.06).round() as i32;
    let pad = if spec.background >> 24 != 0 {
        (px * 0.25).round() as i32
    } else {
        0
    };
    Margins {
        stroke,
        shadow_dx,
        shadow_blur,
        pad,
    }
}

/// The size, in pixels, of the picture [spec] draws on a canvas
/// [canvas_height] pixels tall.
pub fn measure(spec: &TextSpec, canvas_height: u32) -> (u32, u32) {
    let px = pixel_size(spec, canvas_height);
    let face = face_of(spec);
    let scale = PxScale::from(px);
    let lines = layout_lines(&face, scale, spec.letter_spacing * px, &spec.content);
    let (width, height, _) = extent(&face, scale, spec, px, &lines);
    (width, height)
}

/// Picture width and height, and the height of one line.
fn extent(
    face: &Face,
    scale: PxScale,
    spec: &TextSpec,
    px: f32,
    lines: &[Line],
) -> (u32, u32, f32) {
    let scaled = face.font.as_scaled(scale);
    let line_height = scaled.height() * LINE_SPACING;
    let m = margins_of(spec, px);
    let widest = lines.iter().map(|l| l.width).fold(0.0f32, f32::max);
    let lean = if face.fake_italic {
        (scaled.ascent() * SLANT).ceil()
    } else {
        0.0
    };
    let around = 2 * (m.stroke + m.pad) + m.shadow_dx.abs() + 2 * m.shadow_blur;
    let w = (widest + lean).ceil() as i32 + around;
    let h = (line_height * lines.len() as f32).ceil() as i32 + around;
    (w.max(2) as u32 & !1, h.max(2) as u32 & !1, line_height)
}

/// Draws [spec] for a canvas [canvas_height] pixels tall.
pub fn render(spec: &TextSpec, canvas_height: u32) -> RgbaFrame {
    let px = pixel_size(spec, canvas_height);
    let face = face_of(spec);
    let scale = PxScale::from(px);
    let scaled = face.font.as_scaled(scale);
    let lines = layout_lines(&face, scale, spec.letter_spacing * px, &spec.content);
    let (width, height, line_height) = extent(&face, scale, spec, px, &lines);
    let m = margins_of(spec, px);
    let (w, h) = (width as usize, height as usize);

    // Where the glyphs' own box starts inside the picture.
    let inset = m.stroke + m.pad + m.shadow_blur;
    let widest = lines.iter().map(|l| l.width).fold(0.0f32, f32::max);
    let mut fill = vec![0u8; w * h];
    for (row, line) in lines.iter().enumerate() {
        let free = widest - line.width;
        let left = match spec.align {
            TextAlign::Left => 0.0,
            TextAlign::Center => free / 2.0,
            TextAlign::Right => free,
        };
        let baseline = inset as f32
            + row as f32 * line_height
            + (line_height - scaled.height()) / 2.0
            + scaled.ascent();
        for glyph in &line.glyphs {
            let origin = point(inset as f32 + left + glyph.x, baseline);
            let positioned = glyph.id.with_scale_and_position(scale, origin);
            let Some(outlined) = face.font.outline_glyph(positioned) else {
                continue;
            };
            let bounds = outlined.px_bounds();
            outlined.draw(|gx, gy, coverage| {
                let y = bounds.min.y as i32 + gy as i32;
                let shift = if face.fake_italic {
                    ((baseline - y as f32) * SLANT).round() as i32
                } else {
                    0
                };
                let x = bounds.min.x as i32 + gx as i32 + shift;
                if x < 0 || y < 0 || x as usize >= w || y as usize >= h {
                    return;
                }
                let at = &mut fill[y as usize * w + x as usize];
                *at = (*at).max((coverage * 255.0).round() as u8);
            });
        }
    }
    if face.fake_bold {
        fill = dilate(&fill, w, h, ((px * 0.025).round() as i32).max(1));
    }

    let stroke = (m.stroke > 0).then(|| dilate(&fill, w, h, m.stroke));
    let mut out = vec![0u8; w * h * 4];

    if spec.background >> 24 != 0 {
        paint_background(&mut out, w, h, spec.background, px);
    }
    if m.shadow_dx != 0 || m.shadow_blur != 0 {
        let source = stroke.as_deref().unwrap_or(&fill);
        let mut shadow = shift(source, w, h, m.shadow_dx, m.shadow_dx);
        if m.shadow_blur > 0 {
            shadow = box_blur(&shadow, w, h, m.shadow_blur);
        }
        let strength = 0.35 + 0.65 * spec.shadow.clamp(0.0, 1.0);
        let mut colour = [0, 0, 0, (255.0 * strength) as u8];
        // The shadow keeps the text's own transparency.
        colour[3] = (u32::from(colour[3]) * (spec.color >> 24) / 255) as u8;
        cover(&mut out, &shadow, colour);
    }
    if let Some(stroke) = &stroke {
        cover(&mut out, stroke, argb(spec.stroke_color));
    }
    cover(&mut out, &fill, argb(spec.color));

    RgbaFrame {
        width,
        height,
        pts_ms: 0,
        data: out,
    }
}

/// `0xAARRGGBB` as `[r, g, b, a]`.
fn argb(v: u32) -> [u8; 4] {
    [(v >> 16) as u8, (v >> 8) as u8, v as u8, (v >> 24) as u8]
}

/// Draws [colour] through [mask] over [out], straight alpha.
fn cover(out: &mut [u8], mask: &[u8], colour: [u8; 4]) {
    for (d, m) in out.chunks_exact_mut(4).zip(mask) {
        let a = u32::from(*m) * u32::from(colour[3]) / 255;
        if a == 0 {
            continue;
        }
        over(d, colour, a);
    }
}

/// Source-over of [colour] with alpha [a] (0..=255) onto the straight-alpha
/// pixel [d].
fn over(d: &mut [u8], colour: [u8; 4], a: u32) {
    let da = u32::from(d[3]);
    let out_a = a + da * (255 - a) / 255;
    if out_a == 0 {
        return;
    }
    for c in 0..3 {
        let s = u32::from(colour[c]) * a;
        let t = u32::from(d[c]) * da * (255 - a) / 255;
        d[c] = ((s + t) / out_a).min(255) as u8;
    }
    d[3] = out_a.min(255) as u8;
}

/// Fills the whole picture with a rounded rectangle of [colour].
fn paint_background(out: &mut [u8], w: usize, h: usize, colour: u32, px: f32) {
    let radius = (px * 0.2).min(w.min(h) as f32 / 2.0);
    let c = argb(colour);
    for y in 0..h {
        for x in 0..w {
            // Distance outside the corner arcs; 0 inside the shape.
            let cx = (x as f32 + 0.5).clamp(radius, w as f32 - radius);
            let cy = (y as f32 + 0.5).clamp(radius, h as f32 - radius);
            let d = ((x as f32 + 0.5 - cx).powi(2) + (y as f32 + 0.5 - cy).powi(2)).sqrt();
            let edge = (radius - d + 0.5).clamp(0.0, 1.0);
            if edge > 0.0 {
                let a = (f32::from(c[3]) * edge) as u32;
                over(&mut out[(y * w + x) * 4..][..4], c, a);
            }
        }
    }
}

/// Grows [mask] by [radius] pixels in every direction (a round brush).
fn dilate(mask: &[u8], w: usize, h: usize, radius: i32) -> Vec<u8> {
    let mut out = mask.to_vec();
    let r2 = (radius * radius) as f32 + 0.5;
    // Offsets of the brush, with the coverage they keep at the rim.
    let mut brush = Vec::new();
    for dy in -radius..=radius {
        for dx in -radius..=radius {
            if (dx * dx + dy * dy) as f32 <= r2 && (dx, dy) != (0, 0) {
                brush.push((dx, dy));
            }
        }
    }
    for y in 0..h {
        for x in 0..w {
            let v = mask[y * w + x];
            if v == 0 {
                continue;
            }
            for &(dx, dy) in &brush {
                let (nx, ny) = (x as i32 + dx, y as i32 + dy);
                if nx < 0 || ny < 0 || nx as usize >= w || ny as usize >= h {
                    continue;
                }
                let at = &mut out[ny as usize * w + nx as usize];
                *at = (*at).max(v);
            }
        }
    }
    out
}

/// [mask] moved by ([dx], [dy]) pixels.
fn shift(mask: &[u8], w: usize, h: usize, dx: i32, dy: i32) -> Vec<u8> {
    let mut out = vec![0u8; w * h];
    for y in 0..h as i32 {
        let ny = y + dy;
        if ny < 0 || ny >= h as i32 {
            continue;
        }
        for x in 0..w as i32 {
            let nx = x + dx;
            if nx >= 0 && nx < w as i32 {
                out[ny as usize * w + nx as usize] = mask[y as usize * w + x as usize];
            }
        }
    }
    out
}

/// A box blur of [radius] pixels, in two passes.
fn box_blur(mask: &[u8], w: usize, h: usize, radius: i32) -> Vec<u8> {
    let span = (2 * radius + 1) as u32;
    let mut across = vec![0u8; w * h];
    for y in 0..h {
        let row = &mask[y * w..(y + 1) * w];
        for x in 0..w as i32 {
            let sum: u32 = (x - radius..=x + radius)
                .filter(|i| *i >= 0 && (*i as usize) < w)
                .map(|i| u32::from(row[i as usize]))
                .sum();
            across[y * w + x as usize] = (sum / span) as u8;
        }
    }
    let mut out = vec![0u8; w * h];
    for x in 0..w {
        for y in 0..h as i32 {
            let sum: u32 = (y - radius..=y + radius)
                .filter(|i| *i >= 0 && (*i as usize) < h)
                .map(|i| u32::from(across[i as usize * w + x]))
                .sum();
            out[y as usize * w + x] = (sum / span) as u8;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::types::TextAnimation;

    fn spec(content: &str) -> TextSpec {
        TextSpec {
            content: content.to_owned(),
            font: "sans".to_owned(),
            size: 0.1,
            color: 0xFFFF_FFFF,
            bold: false,
            italic: false,
            align: TextAlign::Center,
            stroke_color: 0xFF00_0000,
            stroke_width: 0.0,
            shadow: 0.0,
            background: 0,
            letter_spacing: 0.0,
            animation: TextAnimation::None,
        }
    }

    fn opaque_pixels(frame: &RgbaFrame) -> usize {
        frame.data.chunks_exact(4).filter(|p| p[3] > 128).count()
    }

    #[test]
    fn draws_the_words_with_the_colour_of_the_text() {
        let frame = render(&spec("Hola"), 1000);
        assert!(opaque_pixels(&frame) > 200);
        let p = frame.data.chunks_exact(4).find(|p| p[3] == 255).unwrap();
        assert_eq!(&p[..3], &[255, 255, 255]);
    }

    #[test]
    fn measure_matches_the_picture() {
        let s = spec("Hola mundo");
        let frame = render(&s, 1000);
        assert_eq!(measure(&s, 1000), (frame.width, frame.height));
    }

    #[test]
    fn a_second_line_makes_it_taller_and_not_wider() {
        let one = measure(&spec("Hola"), 1000);
        let two = measure(&spec("Hola\nHola"), 1000);
        assert_eq!(one.0, two.0);
        assert!(two.1 > one.1 * 3 / 2);
    }

    #[test]
    fn size_follows_the_canvas_height() {
        let small = measure(&spec("Hola"), 500);
        let big = measure(&spec("Hola"), 1000);
        assert!(big.0 > small.0 * 3 / 2);
    }

    #[test]
    fn outline_shadow_and_background_make_room() {
        let plain = measure(&spec("Hola"), 1000);
        let mut s = spec("Hola");
        s.stroke_width = 0.08;
        s.shadow = 1.0;
        s.background = 0xAA00_0000;
        let framed = measure(&s, 1000);
        assert!(framed.0 > plain.0 && framed.1 > plain.1);
        let frame = render(&s, 1000);
        // The background reaches the corners' inside, so most of it is drawn.
        assert!(opaque_pixels(&frame) > (frame.width * frame.height) as usize / 2);
    }

    #[test]
    fn every_font_draws_something_and_unknown_ones_fall_back() {
        for family in FAMILIES {
            let id = family.id;
            let mut s = spec("Aa");
            s.font = id.to_owned();
            s.bold = true;
            s.italic = true;
            assert!(opaque_pixels(&render(&s, 600)) > 20, "font {id}");
        }
        let mut s = spec("Aa");
        s.font = "nope".to_owned();
        assert_eq!(measure(&s, 600), measure(&spec("Aa"), 600));
    }

    #[test]
    fn empty_text_is_a_tiny_transparent_picture() {
        let frame = render(&spec(""), 1000);
        assert_eq!(opaque_pixels(&frame), 0);
    }
}
