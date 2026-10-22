use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use std::thread::JoinHandle;

use super::animation::{self, Anim};
use super::effects::{apply_fixed, ColorMatrix};
use super::fx::Fx;
use super::text;
use crate::api::types::{EngineMediaKind, TextAnimation, Timeline, TimelineClip};
use crate::media::video::{DecodeLoad, RgbaFrame, VideoReader};

/// How far ahead a clip's decoder is opened and positioned, so a cut does
/// not stall on a long keyframe interval.
const PREFETCH_MS: i64 = 1_500;

/// Most decoders kept open; the least recently used beyond it are closed.
const MAX_READERS: usize = 4;

/// Frames after which an unused decoder is closed even below the limit
/// (about three seconds at 30 fps).
const IDLE_TICKS: u64 = 90;

/// A clip's decoder: ready, or being opened and positioned on a worker.
enum Slot {
    Ready(VideoReader),
    Warming(JoinHandle<anyhow::Result<VideoReader>>),
}

/// Draws the picture of a timeline at one instant: visual layers from back to
/// front over black, each clip fitted inside the canvas.
///
/// Every clip has its own decoder, opened a little before the clip starts
/// on a worker thread, so a cut lands on a decoder that already sits at its
/// first frame. Decoders unused for the longest are closed past
/// [MAX_READERS].
#[derive(Default)]
pub struct Compositor {
    readers: HashMap<String, (Slot, u64)>,
    broken: HashSet<String>,
    tick: u64,
    /// Threads that share the drawing of a frame, by bands of rows; 0 or 1
    /// draws on the calling thread.
    threads: usize,
    /// How hard the clip decoders work.
    load: Option<DecodeLoad>,
    /// Pictures of the texts drawn lately, by look and canvas height.
    texts: HashMap<String, Arc<RgbaFrame>>,
}

/// Most text pictures kept; past it the cache starts over.
const MAX_TEXTS: usize = 48;

/// Below this many pixels a frame is drawn on one thread: splitting costs
/// more than it saves.
const PARALLEL_PIXELS: u32 = 300_000;

/// The decoder of one clip: its layer, its source and where it starts in it.
pub fn clip_key(layer_index: usize, clip: &TimelineClip) -> String {
    format!(
        "{layer_index}:{}:{}:{}",
        clip.in_ms, clip.reversed, clip.path
    )
}

fn clip_keys(timeline: &Timeline) -> HashSet<String> {
    timeline
        .layers
        .iter()
        .enumerate()
        .flat_map(|(i, l)| l.clips.iter().map(move |c| clip_key(i, c)))
        .collect()
}

/// Readers are kept per layer and file: two layers playing the same file at
/// different times must not fight over one decoder position.
pub fn reader_key(layer_index: usize, path: &str) -> String {
    format!("{layer_index}:{path}")
}

pub fn reader_keys(timeline: &Timeline) -> HashSet<String> {
    timeline
        .layers
        .iter()
        .enumerate()
        .flat_map(|(i, l)| l.clips.iter().map(move |c| reader_key(i, &c.path)))
        .collect()
}

/// Where a source of [sw]x[sh] lands when fitted inside [cw]x[ch].
pub fn fit(sw: u32, sh: u32, cw: u32, ch: u32) -> (u32, u32, u32, u32) {
    if sw == 0 || sh == 0 {
        return (0, 0, cw, ch);
    }
    let scale = (f64::from(cw) / f64::from(sw)).min(f64::from(ch) / f64::from(sh));
    let w = ((f64::from(sw) * scale).round() as u32).clamp(2, cw) & !1;
    let h = ((f64::from(sh) * scale).round() as u32).clamp(2, ch) & !1;
    ((cw - w) / 2, (ch - h) / 2, w, h)
}

/// Where and how big a picture is drawn: its centre, its size before
/// rotation, and how it is turned.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Placement {
    pub cx: f64,
    pub cy: f64,
    pub w: f64,
    pub h: f64,
    pub rotation: f64,
    pub flip_x: bool,
    pub opacity: f32,
    /// The kept part of the source: left and top offsets, width and height,
    /// as fractions of the source.
    pub crop: (f64, f64, f64, f64),
}

/// [place] with the entrance or exit animation of [clip] applied at [t_ms].
fn animated(mut place: Placement, clip: &TimelineClip, t_ms: i64, cw: u32, ch: u32) -> Placement {
    let anim = animation::at(
        clip.anim_in.as_deref(),
        clip.anim_in_ms,
        clip.anim_out.as_deref(),
        clip.anim_out_ms,
        clip.duration_ms(),
        t_ms - clip.start_ms,
    );
    if anim == Anim::NONE {
        return place;
    }
    place.cx += f64::from(anim.dx) * f64::from(cw);
    place.cy += f64::from(anim.dy) * f64::from(ch);
    place.w *= f64::from(anim.scale);
    place.h *= f64::from(anim.scale);
    place.rotation = (place.rotation + f64::from(anim.rotation)).rem_euclid(360.0);
    place.opacity = (place.opacity * anim.opacity).clamp(0.0, 1.0);
    place
}

/// The kept part of [clip]'s source as (left, top, width, height)
/// fractions.
fn crop_of(clip: &TimelineClip) -> (f64, f64, f64, f64) {
    let l = f64::from(clip.crop_left).clamp(0.0, 0.95);
    let t = f64::from(clip.crop_top).clamp(0.0, 0.95);
    let w = (1.0 - l - f64::from(clip.crop_right)).clamp(0.05, 1.0 - l);
    let h = (1.0 - t - f64::from(clip.crop_bottom)).clamp(0.05, 1.0 - t);
    (l, t, w, h)
}

/// The placement of a [sw]x[sh] source of [clip] on a [cw]x[ch] canvas.
pub fn placement(sw: u32, sh: u32, cw: u32, ch: u32, clip: &TimelineClip) -> Placement {
    let crop = crop_of(clip);
    // Fit and fill work on the kept part of the picture.
    let (sw, sh, cw, ch) = (
        f64::from(sw.max(1)) * crop.2,
        f64::from(sh.max(1)) * crop.3,
        f64::from(cw),
        f64::from(ch),
    );
    let base = if clip.fill {
        (cw / sw).max(ch / sh)
    } else {
        (cw / sw).min(ch / sh)
    };
    let scale = base * f64::from(clip.scale.max(0.01));
    Placement {
        cx: cw / 2.0 + f64::from(clip.x) * cw,
        cy: ch / 2.0 + f64::from(clip.y) * ch,
        w: sw * scale,
        h: sh * scale,
        rotation: f64::from(clip.rotation).rem_euclid(360.0),
        flip_x: clip.flip_x,
        opacity: clip.opacity.clamp(0.0, 1.0),
        crop,
    }
}

/// The size a clip's picture is decoded at: its drawn size, but never above
/// the source nor above twice the canvas, so a picture zoomed far in is
/// sampled up instead of being decoded huge.
///
/// With a crop the whole frame is decoded so that its kept part comes out
/// at that size.
pub fn decode_size(sw: u32, sh: u32, cw: u32, ch: u32, clip: &TimelineClip) -> (u32, u32) {
    let place = placement(sw, sh, cw, ch, clip);
    let (_, _, kw, kh) = place.crop;
    let limit = f64::from(cw.max(ch) * 2);
    let shrink = (f64::from(sw) * kw / place.w)
        .min(limit / place.w.max(place.h))
        .min(1.0);
    (
        ((place.w * shrink / kw).round() as u32).max(2),
        ((place.h * shrink / kh).round() as u32).max(2),
    )
}

impl Compositor {
    /// Draws frames with up to [threads] threads (bands of rows).
    pub fn with_threads(threads: usize) -> Self {
        Self {
            threads,
            ..Self::default()
        }
    }

    /// Decodes clips for an export: more decoder threads per file.
    pub fn for_export(threads: usize) -> Self {
        Self {
            threads,
            load: Some(DecodeLoad::Export),
            ..Self::default()
        }
    }

    /// Drops the decoders of clips the timeline no longer has.
    pub fn retain(&mut self, timeline: &Timeline) {
        let used = clip_keys(timeline);
        self.readers.retain(|key, _| used.contains(key));
        self.broken.retain(|key| used.contains(key));
    }

    /// Opens, on a worker, the decoders of the clips that start within
    /// [PREFETCH_MS] after [t_ms], positioned at their first frame.
    fn prefetch(&mut self, timeline: &Timeline, t_ms: i64, cw: u32, ch: u32) {
        for (index, layer) in timeline.layers.iter().enumerate() {
            if matches!(layer.kind, EngineMediaKind::Audio | EngineMediaKind::Text) {
                continue;
            }
            let next = layer
                .clips
                .iter()
                .find(|c| c.start_ms > t_ms && c.start_ms <= t_ms + PREFETCH_MS);
            let Some(clip) = next else { continue };
            let key = clip_key(index, clip);
            if self.readers.contains_key(&key) || self.broken.contains(&key) {
                continue;
            }
            let clip = clip.clone();
            let load = self.load.unwrap_or(DecodeLoad::Preview);
            let handle = std::thread::Builder::new()
                .name("cutter-prefetch".into())
                .spawn(move || -> anyhow::Result<VideoReader> {
                    let mut reader = VideoReader::open_with(&clip.path, load)?;
                    let (sw, sh) = reader.display_size();
                    let (dw, dh) = decode_size(sw, sh, cw, ch, &clip);
                    reader.frame_at(clip.source_ms_at(clip.start_ms), dw, dh, clip.reversed)?;
                    Ok(reader)
                });
            if let Ok(handle) = handle {
                self.readers.insert(key, (Slot::Warming(handle), self.tick));
            }
        }
    }

    /// Closes the least recently used decoders past [MAX_READERS].
    fn evict(&mut self) {
        let tick = self.tick;
        self.readers.retain(|_, (slot, used)| {
            !matches!(slot, Slot::Ready(_)) || tick.saturating_sub(*used) < IDLE_TICKS
        });
        while self.readers.len() > MAX_READERS {
            let oldest = self
                .readers
                .iter()
                .filter(|(_, (slot, used))| matches!(slot, Slot::Ready(_)) && *used < self.tick)
                .min_by_key(|(_, (_, used))| *used)
                .map(|(k, _)| k.clone());
            match oldest {
                Some(key) => {
                    self.readers.remove(&key);
                }
                None => break,
            }
        }
    }

    /// Renders [timeline] at [t_ms] into [out], a [width]x[height] RGBA buffer.
    pub fn render(
        &mut self,
        timeline: &Timeline,
        t_ms: i64,
        width: u32,
        height: u32,
        out: &mut Vec<u8>,
    ) {
        self.tick += 1;
        out.clear();
        out.resize((width * height * 4) as usize, 0);
        for px in out.chunks_exact_mut(4) {
            px[3] = 255;
        }
        // The preview is drawn smaller than the canvas; positions and sizes
        // are in canvas terms, so they scale with it. Pictures are decoded
        // first, then drawn back to front, in bands when the frame is big.
        let mut jobs = Vec::new();
        for (index, layer) in timeline.layers.iter().enumerate().rev() {
            if layer.kind == EngineMediaKind::Audio {
                continue;
            }
            if layer.kind == EngineMediaKind::Text {
                // Texts of one layer may share time: all that are active show.
                for clip in layer.clips.iter().filter(|c| c.is_active_at(t_ms)) {
                    if let Some((frame, place)) = self.text_frame(clip, t_ms, width, height) {
                        jobs.push((frame, place, None, true));
                    }
                }
                continue;
            }
            let Some(clip) = layer.clips.iter().find(|c| c.is_active_at(t_ms)) else {
                continue;
            };
            if clip.opacity <= 0.0 {
                continue;
            }
            let key = clip_key(index, clip);
            if let Some((frame, place)) = self.frame_for(&key, clip, t_ms, width, height) {
                let frame = match Fx::of(clip) {
                    Some(fx) => Arc::new(fx.apply(&frame)),
                    None => frame,
                };
                let place = animated(place, clip, t_ms, width, height);
                let matrix = ColorMatrix::for_clip(clip).map(|m| m.fixed());
                let blend = clip.kind == EngineMediaKind::Image || place.opacity < 1.0;
                jobs.push((frame, place, matrix, blend));
            }
        }
        let threads = if width * height >= PARALLEL_PIXELS {
            self.threads.max(1)
        } else {
            1
        };
        if threads <= 1 {
            for (frame, place, matrix, blend) in &jobs {
                draw(
                    out,
                    width,
                    height,
                    0..height,
                    frame,
                    place,
                    matrix.as_ref(),
                    *blend,
                );
            }
        } else {
            let rows = height.div_ceil(threads as u32);
            let jobs = &jobs;
            std::thread::scope(|scope| {
                for (i, band) in out.chunks_mut((rows * width * 4) as usize).enumerate() {
                    let y0 = i as u32 * rows;
                    let y1 = (y0 + rows).min(height);
                    scope.spawn(move || {
                        for (frame, place, matrix, blend) in jobs {
                            draw(
                                band,
                                width,
                                height,
                                y0..y1,
                                frame,
                                place,
                                matrix.as_ref(),
                                *blend,
                            );
                        }
                    });
                }
            });
        }
        self.prefetch(timeline, t_ms, width, height);
        self.evict();
    }

    /// The picture of a text clip at [t_ms] and where it goes on a
    /// [cw]x[ch] canvas, with its entrance or exit applied.
    fn text_frame(
        &mut self,
        clip: &TimelineClip,
        t_ms: i64,
        cw: u32,
        ch: u32,
    ) -> Option<(Arc<RgbaFrame>, Placement)> {
        let spec = clip.text.as_ref()?;
        if clip.opacity <= 0.0 || spec.content.trim().is_empty() {
            return None;
        }
        let key = {
            let mut look = spec.clone();
            look.animation = TextAnimation::None;
            format!("{ch}|{look:?}")
        };
        if self.texts.len() >= MAX_TEXTS && !self.texts.contains_key(&key) {
            self.texts.clear();
        }
        let frame = self
            .texts
            .entry(key)
            .or_insert_with(|| Arc::new(text::render(spec, ch)))
            .clone();
        let mut scale = f64::from(clip.scale.max(0.01));
        let mut opacity = clip.opacity.clamp(0.0, 1.0);
        let mut lift = 0.0;
        let progress = text_progress(clip, t_ms);
        match spec.animation {
            TextAnimation::None => {}
            TextAnimation::Fade => opacity *= progress as f32,
            TextAnimation::Pop => {
                // Grows from small with a little overshoot.
                let back =
                    1.0 + 2.70158 * (progress - 1.0).powi(3) + 1.70158 * (progress - 1.0).powi(2);
                scale *= 0.5 + 0.5 * back;
                opacity *= progress.min(1.0) as f32;
            }
            TextAnimation::SlideUp => {
                let eased = 1.0 - (1.0 - progress).powi(3);
                lift = (1.0 - eased) * 0.06 * f64::from(ch);
                opacity *= eased as f32;
            }
        }
        let place = Placement {
            cx: f64::from(cw) / 2.0 + f64::from(clip.x) * f64::from(cw),
            cy: f64::from(ch) / 2.0 + f64::from(clip.y) * f64::from(ch) + lift,
            w: f64::from(frame.width) * scale,
            h: f64::from(frame.height) * scale,
            rotation: f64::from(clip.rotation).rem_euclid(360.0),
            flip_x: clip.flip_x,
            opacity,
            crop: (0.0, 0.0, 1.0, 1.0),
        };
        Some((frame, place))
    }

    fn frame_for(
        &mut self,
        key: &str,
        clip: &TimelineClip,
        t_ms: i64,
        cw: u32,
        ch: u32,
    ) -> Option<(Arc<RgbaFrame>, Placement)> {
        if self.broken.contains(key) {
            return None;
        }
        let tick = self.tick;
        let slot = match self.readers.remove(key) {
            Some((Slot::Ready(reader), _)) => Ok(reader),
            // Wait for a decoder still being positioned: it is nearly there.
            Some((Slot::Warming(handle), _)) => handle
                .join()
                .unwrap_or_else(|_| Err(anyhow::anyhow!("prefetch panicked"))),
            None => VideoReader::open_with(&clip.path, self.load.unwrap_or(DecodeLoad::Preview)),
        };
        let mut reader = match slot {
            Ok(reader) => reader,
            Err(e) => {
                crate::diagnostics::error(format!("cannot read {}: {e:#}", clip.path));
                self.broken.insert(key.to_owned());
                return None;
            }
        };
        let (sw, sh) = reader.display_size();
        let place = placement(sw, sh, cw, ch, clip);
        let (dw, dh) = decode_size(sw, sh, cw, ch, clip);
        let result = reader.frame_at(clip.source_ms_at(t_ms), dw, dh, clip.reversed);
        self.readers
            .insert(key.to_owned(), (Slot::Ready(reader), tick));
        match result {
            Ok(Some(frame)) => Some((frame, place)),
            Ok(None) => None,
            Err(e) => {
                crate::diagnostics::warn(format!("decode {} at {t_ms} ms: {e:#}", clip.path));
                None
            }
        }
    }
}

/// How far into its entrance or exit a text clip is at [t_ms]: 0 when it
/// has just appeared or is about to go, 1 in between.
fn text_progress(clip: &TimelineClip, t_ms: i64) -> f64 {
    let ramp = TEXT_RAMP_MS.min(clip.duration_ms() / 3).max(1) as f64;
    let since = (t_ms - clip.start_ms) as f64 / ramp;
    let until = (clip.end_ms() - t_ms) as f64 / ramp;
    since.min(until).clamp(0.0, 1.0)
}

/// How long a text's entrance or exit lasts, at most.
const TEXT_RAMP_MS: i64 = 350;

/// Draws [frame] at [place]: a straight copy when the picture is upright and
/// at its decoded size, otherwise sampled through the inverse transform.
/// Draws [frame] at [place] into [band], the rows [rows] of a [cw]x[ch]
/// canvas.
#[allow(clippy::too_many_arguments)]
fn draw(
    band: &mut [u8],
    cw: u32,
    ch: u32,
    rows: std::ops::Range<u32>,
    frame: &RgbaFrame,
    place: &Placement,
    matrix: Option<&[[i32; 4]; 3]>,
    blend: bool,
) {
    let upright = place.rotation.abs() < 1e-6 && !place.flip_x;
    let (l, t, kw, kh) = place.crop;
    let sub = (
        (l * f64::from(frame.width)).round() as u32,
        (t * f64::from(frame.height)).round() as u32,
        ((kw * f64::from(frame.width)).round() as u32).clamp(1, frame.width),
        ((kh * f64::from(frame.height)).round() as u32).clamp(1, frame.height),
    );
    let exact = (place.w.round() as u32) == sub.2 && (place.h.round() as u32) == sub.3;
    if upright && exact {
        let x = (place.cx - place.w / 2.0).round() as i64;
        let y = (place.cy - place.h / 2.0).round() as i64;
        copy(
            band,
            cw,
            rows,
            frame,
            sub,
            x,
            y,
            matrix,
            blend,
            place.opacity,
        );
    } else {
        sample(band, cw, ch, rows, frame, place, matrix);
    }
}

#[inline]
fn put(d: &mut [u8], r: u8, g: u8, b: u8, alpha: u32) {
    if alpha >= 255 {
        d[0] = r;
        d[1] = g;
        d[2] = b;
    } else if alpha > 0 {
        let mix =
            |s: u8, t: u8| ((u32::from(s) * alpha + u32::from(t) * (255 - alpha)) / 255) as u8;
        d[0] = mix(r, d[0]);
        d[1] = mix(g, d[1]);
        d[2] = mix(b, d[2]);
    }
    d[3] = 255;
}

/// Copies [frame] with its top-left corner at ([x], [y]), clipped to the
/// canvas.
#[allow(clippy::too_many_arguments)]
fn copy(
    band: &mut [u8],
    cw: u32,
    rows: std::ops::Range<u32>,
    frame: &RgbaFrame,
    sub: (u32, u32, u32, u32),
    x: i64,
    y: i64,
    matrix: Option<&[[i32; 4]; 3]>,
    blend: bool,
    opacity: f32,
) {
    let (fw, fh) = (i64::from(sub.2), i64::from(sub.3));
    let (x0, y0) = (x.max(0), y.max(i64::from(rows.start)));
    let (x1, y1) = (
        (x + fw).min(i64::from(cw)),
        (y + fh).min(i64::from(rows.end)),
    );
    if x0 >= x1 || y0 >= y1 {
        return;
    }
    let w = (x1 - x0) as usize;
    let op = (opacity * 255.0).round() as u32;
    for row in y0..y1 {
        let sy = (row - y) as usize + sub.1 as usize;
        let sx = (x0 - x) as usize + sub.0 as usize;
        let src = &frame.data[(sy * frame.width as usize + sx) * 4..][..w * 4];
        let start = ((row as usize - rows.start as usize) * cw as usize + x0 as usize) * 4;
        let dst = &mut band[start..start + w * 4];
        if matrix.is_none() && !blend {
            dst.copy_from_slice(src);
            continue;
        }
        for (d, s) in dst.chunks_exact_mut(4).zip(src.chunks_exact(4)) {
            let (r, g, b) = match matrix {
                Some(m) => apply_fixed(m, s[0], s[1], s[2]),
                None => (s[0], s[1], s[2]),
            };
            let alpha = if blend {
                u32::from(s[3]) * op / 255
            } else {
                255
            };
            put(d, r, g, b, alpha);
        }
    }
}

/// Draws [frame] scaled, rotated and mirrored: every canvas pixel inside the
/// turned rectangle is mapped back into the frame and sampled bilinearly.
fn sample(
    band: &mut [u8],
    cw: u32,
    ch: u32,
    rows: std::ops::Range<u32>,
    frame: &RgbaFrame,
    place: &Placement,
    matrix: Option<&[[i32; 4]; 3]>,
) {
    let (sin, cos) = place.rotation.to_radians().sin_cos();
    let (hw, hh) = (place.w / 2.0, place.h / 2.0);
    // Bounding box of the turned rectangle.
    let ex = hw * cos.abs() + hh * sin.abs();
    let ey = hw * sin.abs() + hh * cos.abs();
    let x0 = (place.cx - ex).floor().max(0.0) as u32;
    let y0 = ((place.cy - ey).floor().max(0.0) as u32).max(rows.start);
    let x1 = ((place.cx + ex).ceil() as i64).clamp(0, i64::from(cw)) as u32;
    let y1 = (((place.cy + ey).ceil() as i64).clamp(0, i64::from(ch)) as u32).min(rows.end);
    let (fw, fh) = (frame.width as usize, frame.height as usize);
    let (l, t, kw, kh) = place.crop;
    // Frame pixels per drawn pixel, and where the kept part starts.
    let (kx, ky) = (
        frame.width as f64 * kw / place.w,
        frame.height as f64 * kh / place.h,
    );
    let (ox, oy) = (l * frame.width as f64, t * frame.height as f64);
    let op = place.opacity;
    for py in y0..y1 {
        let dy = f64::from(py) + 0.5 - place.cy;
        for px in x0..x1 {
            let dx = f64::from(px) + 0.5 - place.cx;
            let mut ux = dx * cos + dy * sin;
            let uy = -dx * sin + dy * cos;
            if place.flip_x {
                ux = -ux;
            }
            if ux < -hw || ux >= hw || uy < -hh || uy >= hh {
                continue;
            }
            // Position in the frame, between pixel centres.
            let sx = (ox + (ux + hw) * kx - 0.5).clamp(0.0, (fw - 1) as f64);
            let sy = (oy + (uy + hh) * ky - 0.5).clamp(0.0, (fh - 1) as f64);
            let (ix, iy) = (sx as usize, sy as usize);
            let (ax, ay) = ((sx - ix as f64) as f32, (sy - iy as f64) as f32);
            let (jx, jy) = ((ix + 1).min(fw - 1), (iy + 1).min(fh - 1));
            let at = |x: usize, y: usize, c: usize| f32::from(frame.data[(y * fw + x) * 4 + c]);
            let mut px_out = [0f32; 4];
            for (c, v) in px_out.iter_mut().enumerate() {
                let top = at(ix, iy, c) * (1.0 - ax) + at(jx, iy, c) * ax;
                let bottom = at(ix, jy, c) * (1.0 - ax) + at(jx, jy, c) * ax;
                *v = top * (1.0 - ay) + bottom * ay;
            }
            let (r, g, b) = (px_out[0] as u8, px_out[1] as u8, px_out[2] as u8);
            let (r, g, b) = match matrix {
                Some(m) => apply_fixed(m, r, g, b),
                None => (r, g, b),
            };
            let alpha = (px_out[3] * op).round() as u32;
            let i = (((py - rows.start) * cw + px) * 4) as usize;
            put(&mut band[i..i + 4], r, g, b, alpha);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::fit;

    #[test]
    fn landscape_source_fits_a_vertical_canvas_with_bars() {
        let (x, y, w, h) = fit(1920, 1080, 1080, 1920);
        assert_eq!((x, w), (0, 1080));
        assert_eq!(h, 608);
        assert_eq!(y, (1920 - 608) / 2);
    }
}

#[cfg(test)]
mod render_tests {
    use super::Compositor;
    use crate::api::types::EngineMediaKind;
    use crate::test_support::{clip, fixtures, layer, vertical};

    fn pixel(buf: &[u8], w: u32, x: u32, y: u32) -> [u8; 4] {
        let i = ((y * w + x) * 4) as usize;
        [buf[i], buf[i + 1], buf[i + 2], buf[i + 3]]
    }

    #[test]
    fn draws_a_landscape_clip_between_black_bars() {
        let f = fixtures();
        let timeline = vertical(vec![layer(
            EngineMediaKind::Video,
            vec![clip(&f.video, EngineMediaKind::Video, 0, 0, 3000)],
        )]);
        let mut out = Vec::new();
        Compositor::default().render(&timeline, 500, 360, 640, &mut out);
        assert_eq!(out.len(), 360 * 640 * 4);
        assert_eq!(pixel(&out, 360, 180, 10), [0, 0, 0, 255]);
        let middle: u32 = (0..360)
            .map(|x| {
                pixel(&out, 360, x, 320)[..3]
                    .iter()
                    .map(|v| u32::from(*v))
                    .sum::<u32>()
            })
            .sum();
        assert!(middle > 0);
    }

    #[test]
    fn the_front_layer_covers_the_back_one() {
        let f = fixtures();
        let mut front = clip(&f.rotated, EngineMediaKind::Video, 0, 0, 3000);
        front.filter = Some("mono".into());
        let timeline = vertical(vec![
            layer(EngineMediaKind::Video, vec![front]),
            layer(
                EngineMediaKind::Video,
                vec![clip(&f.video, EngineMediaKind::Video, 0, 0, 3000)],
            ),
        ]);
        let mut out = Vec::new();
        Compositor::default().render(&timeline, 500, 360, 640, &mut out);
        // The rotated clip fills the vertical canvas, in grey.
        for (x, y) in [(10, 10), (180, 320), (350, 630)] {
            let [r, g, b, _] = pixel(&out, 360, x, y);
            assert!(
                r.abs_diff(g) <= 2 && g.abs_diff(b) <= 2,
                "({x},{y}) = {r},{g},{b}"
            );
        }
    }

    #[test]
    fn nothing_is_drawn_where_no_clip_plays() {
        let f = fixtures();
        let timeline = vertical(vec![layer(
            EngineMediaKind::Video,
            vec![clip(&f.video, EngineMediaKind::Video, 1000, 0, 500)],
        )]);
        let mut out = Vec::new();
        Compositor::default().render(&timeline, 0, 360, 640, &mut out);
        assert!(out.chunks_exact(4).all(|p| p == [0, 0, 0, 255]));
    }

    fn render_one(edit: impl FnOnce(&mut crate::api::types::TimelineClip)) -> Vec<u8> {
        let f = fixtures();
        let mut c = clip(&f.video, EngineMediaKind::Video, 0, 0, 3000);
        edit(&mut c);
        let timeline = vertical(vec![layer(EngineMediaKind::Video, vec![c])]);
        let mut out = Vec::new();
        Compositor::default().render(&timeline, 500, 360, 640, &mut out);
        out
    }

    fn is_black(p: [u8; 4]) -> bool {
        p[0] < 8 && p[1] < 8 && p[2] < 8
    }

    #[test]
    fn fill_covers_the_whole_canvas() {
        let out = render_one(|c| c.fill = true);
        for (x, y) in [(2, 2), (357, 2), (2, 637), (357, 637)] {
            assert!(!is_black(pixel(&out, 360, x, y)), "({x},{y})");
        }
    }

    #[test]
    fn an_offset_moves_the_picture() {
        // Fitted, the picture spans the full width; moved half a canvas to
        // the right, its left half is empty.
        let out = render_one(|c| c.x = 0.5);
        assert!(is_black(pixel(&out, 360, 90, 320)));
        assert!(!is_black(pixel(&out, 360, 270, 320)));
    }

    #[test]
    fn a_quarter_turn_stands_a_landscape_picture_up() {
        // Turned 90 degrees, the 360x202 fitted strip becomes a 202 px wide,
        // 360 px tall column in the middle (y 140..500).
        let out = render_one(|c| c.rotation = 90.0);
        assert!(!is_black(pixel(&out, 360, 180, 150)));
        assert!(is_black(pixel(&out, 360, 180, 100)));
        assert!(is_black(pixel(&out, 360, 20, 320)));
    }

    fn brightness_sum(b: &[u8]) -> u64 {
        b.chunks_exact(4)
            .map(|p| u64::from(p[0]) + u64::from(p[1]) + u64::from(p[2]))
            .sum()
    }

    #[test]
    fn a_fade_in_is_dim_at_the_start_of_the_clip() {
        let full = render_one(|_| {});
        let dim = render_one(|c| {
            c.anim_in = Some("fade".into());
            c.anim_in_ms = 3000;
        });
        let ratio = brightness_sum(&dim) as f64 / brightness_sum(&full) as f64;
        assert!((0.2..0.7).contains(&ratio), "{ratio}");
    }

    #[test]
    fn an_exit_animation_leaves_the_middle_of_the_clip_alone() {
        let full = render_one(|_| {});
        let same = render_one(|c| {
            c.anim_out = Some("spin".into());
            c.anim_out_ms = 1000;
        });
        assert_eq!(full, same);
    }

    #[test]
    fn a_slide_in_moves_the_picture_off_its_place() {
        let full = render_one(|_| {});
        let moved = render_one(|c| {
            c.anim_in = Some("slide_left".into());
            c.anim_in_ms = 3000;
        });
        assert_ne!(full, moved);
    }

    #[test]
    fn half_opacity_darkens_over_black() {
        let full = render_one(|_| {});
        let half = render_one(|c| c.opacity = 0.5);
        let sum = |b: &[u8]| -> u64 {
            b.chunks_exact(4)
                .map(|p| u64::from(p[0]) + u64::from(p[1]) + u64::from(p[2]))
                .sum()
        };
        let ratio = sum(&half) as f64 / sum(&full) as f64;
        assert!((0.4..0.6).contains(&ratio), "{ratio}");
    }

    #[test]
    fn a_mirror_swaps_left_and_right() {
        let plain = render_one(|_| {});
        let mirrored = render_one(|c| c.flip_x = true);
        let a = pixel(&plain, 360, 30, 320);
        let b = pixel(&mirrored, 360, 329, 320);
        for c in 0..3 {
            assert!(a[c].abs_diff(b[c]) < 40, "{a:?} vs {b:?}");
        }
    }

    #[test]
    fn a_crop_keeps_part_of_the_picture_and_fills_with_it() {
        // Keeping the middle third of a 640x360 picture leaves a 213x360
        // part, near the 360x640 canvas shape: fitted, it covers almost all.
        let out = render_one(|c| {
            c.crop_left = 1.0 / 3.0;
            c.crop_right = 1.0 / 3.0;
        });
        assert!(!is_black(pixel(&out, 360, 180, 20)));
        assert!(!is_black(pixel(&out, 360, 180, 620)));
        let full = render_one(|_| {});
        assert!(is_black(pixel(&full, 360, 180, 20)));
    }

    #[test]
    fn a_zoomed_picture_is_not_decoded_huge() {
        // Scale 10 on a 360x640 canvas: the decode is capped, the render
        // still fills the frame.
        let out = render_one(|c| c.scale = 10.0);
        assert!(!is_black(pixel(&out, 360, 180, 320)));
        assert!(crate::diagnostics::snapshot().cache_bytes < 64 * 1024 * 1024);
    }

    fn text_clip(words: &str, start: i64, end: i64) -> crate::api::types::TimelineClip {
        use crate::api::types::{TextAlign, TextAnimation, TextSpec};
        let mut c = clip("", EngineMediaKind::Text, start, 0, end - start);
        c.text = Some(TextSpec {
            content: words.to_owned(),
            font: "sans".to_owned(),
            size: 0.2,
            color: 0xFFFF_0000,
            bold: true,
            italic: false,
            align: TextAlign::Center,
            stroke_color: 0xFF00_0000,
            stroke_width: 0.0,
            shadow: 0.0,
            background: 0,
            letter_spacing: 0.0,
            animation: TextAnimation::None,
        });
        c
    }

    fn red_pixels(buf: &[u8]) -> usize {
        buf.chunks_exact(4)
            .filter(|p| p[0] > 200 && p[1] < 60 && p[2] < 60)
            .count()
    }

    #[test]
    fn draws_a_text_only_while_its_clip_is_active() {
        let timeline = vertical(vec![layer(
            EngineMediaKind::Text,
            vec![text_clip("Hola", 1000, 2000)],
        )]);
        let mut compositor = Compositor::default();
        let mut out = Vec::new();
        compositor.render(&timeline, 500, 360, 640, &mut out);
        assert_eq!(red_pixels(&out), 0);
        compositor.render(&timeline, 1500, 360, 640, &mut out);
        assert!(red_pixels(&out) > 300);
        compositor.render(&timeline, 2500, 360, 640, &mut out);
        assert_eq!(red_pixels(&out), 0);
    }

    #[test]
    fn texts_of_one_layer_that_overlap_both_show() {
        let mut upper = text_clip("Arriba", 0, 2000);
        upper.y = -0.3;
        let mut lower = text_clip("Abajo", 500, 2000);
        lower.y = 0.3;
        let timeline = vertical(vec![layer(EngineMediaKind::Text, vec![upper, lower])]);
        let mut out = Vec::new();
        let mut compositor = Compositor::default();
        compositor.render(&timeline, 400, 360, 640, &mut out);
        let alone = red_pixels(&out);
        compositor.render(&timeline, 1000, 360, 640, &mut out);
        assert!(red_pixels(&out) > alone * 3 / 2);
    }

    #[test]
    fn a_text_moves_with_its_position() {
        let mut moved = text_clip("Hola", 0, 1000);
        moved.x = 0.3;
        moved.y = -0.4;
        let timeline = vertical(vec![layer(EngineMediaKind::Text, vec![moved])]);
        let mut out = Vec::new();
        Compositor::default().render(&timeline, 500, 360, 640, &mut out);
        let (mut sx, mut sy, mut n) = (0usize, 0usize, 0usize);
        for (i, p) in out.chunks_exact(4).enumerate() {
            if p[0] > 200 && p[1] < 60 {
                sx += i % 360;
                sy += i / 360;
                n += 1;
            }
        }
        assert!(n > 0);
        // Centre of the red pixels: right of and above the canvas centre.
        assert!(sx / n > 180 + 60 && sy / n < 320 - 150);
    }

    #[test]
    fn a_fade_starts_invisible_and_ends_visible() {
        use crate::api::types::TextAnimation;
        let mut c = text_clip("Hola", 0, 3000);
        c.text.as_mut().unwrap().animation = TextAnimation::Fade;
        let timeline = vertical(vec![layer(EngineMediaKind::Text, vec![c])]);
        let mut out = Vec::new();
        let mut compositor = Compositor::default();
        compositor.render(&timeline, 0, 360, 640, &mut out);
        assert_eq!(red_pixels(&out), 0);
        compositor.render(&timeline, 1500, 360, 640, &mut out);
        assert!(red_pixels(&out) > 300);
    }
}

#[cfg(test)]
pub use bench::stress_timeline as bench_timeline;

/// Stress benchmark with real media: `CUTTER_BENCH=1 cargo test --release
/// bench_ -- --ignored --nocapture`. Skipped when the files are missing.
#[cfg(test)]
mod bench {
    use std::time::Instant;

    use super::Compositor;
    use crate::api::types::{EngineMediaKind, Timeline};
    use crate::test_support::{clip, layer};

    const VIDEO: &str = "/home/omar/personal/my-nvim-setup/video/out/leader.silent.mp4";
    const SHOTS: &str = "/home/omar/personal/my-nvim-setup/brand/shots";

    pub fn stress_timeline(width: u32, height: u32) -> Option<Timeline> {
        if !std::path::Path::new(VIDEO).exists() {
            return None;
        }
        let shot = |n: &str| format!("{SHOTS}/{n}.png");
        // Main track: eight cuts of the same 1080p video, out of order.
        let mut main = Vec::new();
        let mut at = 0;
        for (i, src) in [0, 40_000, 10_000, 90_000, 20_000, 120_000, 60_000, 5_000]
            .iter()
            .enumerate()
        {
            let len = 2_500 + (i as i64 % 3) * 500;
            main.push(clip(VIDEO, EngineMediaKind::Video, at, *src, src + len));
            at += len;
        }
        // A second video layer as picture-in-picture, scaled and rotated.
        let mut pip = clip(
            VIDEO,
            EngineMediaKind::Video,
            1_000,
            70_000,
            70_000 + at - 2_000,
        );
        pip.scale = 0.4;
        pip.x = 0.25;
        pip.y = -0.25;
        pip.rotation = 8.0;
        // Images: a sticker row over everything.
        let mut images = Vec::new();
        for (i, n) in ["review", "commit", "tests", "fix"].iter().enumerate() {
            let mut c = clip(&shot(n), EngineMediaKind::Image, i as i64 * 5_000, 0, 4_000);
            c.scale = 0.35;
            c.y = 0.3;
            c.opacity = 0.9;
            images.push(c);
        }
        Some(Timeline {
            width,
            height,
            fps: 30,
            layers: vec![
                layer(EngineMediaKind::Image, images),
                layer(EngineMediaKind::Video, vec![pip]),
                layer(EngineMediaKind::Video, main),
            ],
        })
    }

    #[test]
    #[ignore]
    fn bench_preview_many_layers() {
        let Some(tl) = stress_timeline(1080, 1920) else {
            return;
        };
        let (w, h) = crate::playback::preview_size(&tl, (720, 1280));
        // Paced like the player: one frame every 33 ms of wall time.
        let mut c = Compositor::with_threads(2);
        let mut out = Vec::new();
        let total = tl.duration_ms();
        let started = Instant::now();
        let (mut worst, mut late, mut n, mut sum) = (0f64, 0, 0, 0f64);
        let mut t = 0;
        while t < total {
            let f = Instant::now();
            c.render(&tl, t, w, h, &mut out);
            let ms = f.elapsed().as_secs_f64() * 1000.0;
            worst = worst.max(ms);
            sum += ms;
            if ms > 33.3 {
                late += 1;
            }
            n += 1;
            t += 33;
            let due = std::time::Duration::from_millis(t as u64);
            if let Some(rest) = due.checked_sub(started.elapsed()) {
                std::thread::sleep(rest);
            }
        }
        eprintln!(
            "BENCH preview {w}x{h} real time: {n} frames, avg {:.1} ms, worst {worst:.1} ms, {late} over 33 ms",
            sum / n as f64
        );
    }
}
