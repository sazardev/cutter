//! Spatial effects on a clip's picture: pixelate, blur, sharpen, grain and
//! vignette. Each strength is 0.0..=1.0 and 0 leaves the picture alone.

use crate::api::types::TimelineClip;
use crate::media::video::RgbaFrame;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Fx {
    pub blur: f32,
    pub vignette: f32,
    pub grain: f32,
    pub pixelate: f32,
    pub sharpen: f32,
}

impl Fx {
    pub fn of(clip: &TimelineClip) -> Option<Fx> {
        let s = |v: f32| if v.is_nan() { 0.0 } else { v.clamp(0.0, 1.0) };
        let fx = Fx {
            blur: s(clip.blur),
            vignette: s(clip.vignette),
            grain: s(clip.grain),
            pixelate: s(clip.pixelate),
            sharpen: s(clip.sharpen),
        };
        (fx != Fx::default()).then_some(fx)
    }

    /// A processed copy of [frame].
    pub fn apply(&self, frame: &RgbaFrame) -> RgbaFrame {
        let (w, h) = (frame.width as usize, frame.height as usize);
        let mut data = frame.data.clone();
        if self.pixelate > 0.0 {
            pixelate(&mut data, w, h, self.pixelate);
        }
        if self.blur > 0.0 {
            let radius = (self.blur * w.min(h) as f32 * 0.04).round() as usize;
            box_blur(&mut data, w, h, radius.max(1));
            box_blur(&mut data, w, h, radius.max(1));
        }
        if self.sharpen > 0.0 {
            sharpen(&mut data, w, h, self.sharpen);
        }
        if self.grain > 0.0 {
            grain(&mut data, w, h, self.grain, frame.pts_ms);
        }
        if self.vignette > 0.0 {
            vignette(&mut data, w, h, self.vignette);
        }
        RgbaFrame {
            width: frame.width,
            height: frame.height,
            pts_ms: frame.pts_ms,
            data,
        }
    }
}

/// Replaces each block with its top-left pixel; blocks grow up to 1/12 of
/// the short side.
fn pixelate(data: &mut [u8], w: usize, h: usize, amount: f32) {
    let block = (1.0 + amount * (w.min(h) as f32 / 12.0)).round() as usize;
    if block < 2 {
        return;
    }
    for by in (0..h).step_by(block) {
        for bx in (0..w).step_by(block) {
            let src = (by * w + bx) * 4;
            let px = [data[src], data[src + 1], data[src + 2], data[src + 3]];
            for y in by..(by + block).min(h) {
                for x in bx..(bx + block).min(w) {
                    let d = (y * w + x) * 4;
                    data[d..d + 4].copy_from_slice(&px);
                }
            }
        }
    }
}

/// A separable box blur of [radius] pixels, edges clamped.
fn box_blur(data: &mut [u8], w: usize, h: usize, radius: usize) {
    let mut tmp = vec![0u8; data.len()];
    blur_pass(data, &mut tmp, w, h, radius, true);
    blur_pass(&tmp, data, w, h, radius, false);
}

fn blur_pass(src: &[u8], dst: &mut [u8], w: usize, h: usize, radius: usize, horizontal: bool) {
    let (len, lines, step, line_step) = if horizontal {
        (w, h, 4, w * 4)
    } else {
        (h, w, w * 4, 4)
    };
    let r = radius as isize;
    let window = (2 * r + 1) as u32;
    for line in 0..lines {
        let base = line * line_step;
        let at = |i: isize| base + (i.clamp(0, len as isize - 1) as usize) * step;
        let mut sum = [0u32; 4];
        for i in -r..=r {
            let p = at(i);
            for c in 0..4 {
                sum[c] += u32::from(src[p + c]);
            }
        }
        for i in 0..len as isize {
            let out = at(i);
            for c in 0..4 {
                dst[out + c] = ((sum[c] + window / 2) / window) as u8;
            }
            let (add, sub) = (at(i + r + 1), at(i - r));
            for c in 0..4 {
                sum[c] = sum[c] + u32::from(src[add + c]) - u32::from(src[sub + c]);
            }
        }
    }
}

/// Unsharp mask: the picture plus [amount] times what a 1 px blur removes.
fn sharpen(data: &mut [u8], w: usize, h: usize, amount: f32) {
    let mut soft = data.to_vec();
    box_blur(&mut soft, w, h, 1);
    let gain = amount * 2.0;
    for (px, blurred) in data.chunks_exact_mut(4).zip(soft.chunks_exact(4)) {
        for c in 0..3 {
            let v = f32::from(px[c]) + gain * (f32::from(px[c]) - f32::from(blurred[c]));
            px[c] = v.clamp(0.0, 255.0) as u8;
        }
    }
}

/// Film grain: noise that changes every 1/24 s and is the same on every
/// render of a given instant, so scrubbing and export agree.
fn grain(data: &mut [u8], w: usize, h: usize, amount: f32, pts_ms: i64) {
    let seed = (pts_ms.max(0) as u32 / 42).wrapping_mul(0x9E37_79B9);
    let strength = amount * 60.0;
    for y in 0..h {
        for x in 0..w {
            let mut n =
                (x as u32).wrapping_mul(0x85EB_CA6B) ^ (y as u32).wrapping_mul(0xC2B2_AE35) ^ seed;
            n ^= n >> 15;
            n = n.wrapping_mul(0x2C1B_3C6D);
            n ^= n >> 12;
            let noise = (n & 0xFF) as f32 / 127.5 - 1.0;
            let d = (y * w + x) * 4;
            let delta = noise * strength;
            for c in 0..3 {
                data[d + c] = (f32::from(data[d + c]) + delta).clamp(0.0, 255.0) as u8;
            }
        }
    }
}

/// Darkens toward the corners, none at the centre.
fn vignette(data: &mut [u8], w: usize, h: usize, amount: f32) {
    let (cx, cy) = (w as f32 / 2.0, h as f32 / 2.0);
    for y in 0..h {
        let dy = (y as f32 + 0.5 - cy) / cy;
        for x in 0..w {
            let dx = (x as f32 + 0.5 - cx) / cx;
            let d = ((dx * dx + dy * dy) / 2.0).sqrt();
            let falloff = ((d - 0.35) / 0.65).clamp(0.0, 1.0);
            let k = 1.0 - amount * falloff * falloff;
            let i = (y * w + x) * 4;
            for c in 0..3 {
                data[i + c] = (f32::from(data[i + c]) * k) as u8;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame(w: u32, h: u32, f: impl Fn(u32, u32) -> u8) -> RgbaFrame {
        let mut data = Vec::new();
        for y in 0..h {
            for x in 0..w {
                let v = f(x, y);
                data.extend_from_slice(&[v, v, v, 255]);
            }
        }
        RgbaFrame {
            width: w,
            height: h,
            pts_ms: 0,
            data,
        }
    }

    fn px(f: &RgbaFrame, x: u32, y: u32) -> u8 {
        f.data[((y * f.width + x) * 4) as usize]
    }

    fn only(set: impl FnOnce(&mut Fx)) -> Fx {
        let mut fx = Fx::default();
        set(&mut fx);
        fx
    }

    #[test]
    fn no_strength_means_no_effect() {
        use crate::api::types::EngineMediaKind::Video;
        let mut c = crate::test_support::clip("", Video, 0, 0, 1000);
        assert!(Fx::of(&c).is_none());
        c.blur = 0.5;
        c.grain = 7.0;
        let fx = Fx::of(&c).unwrap();
        assert_eq!((fx.blur, fx.grain), (0.5, 1.0));
    }

    #[test]
    fn blur_spreads_an_edge() {
        let f = frame(40, 40, |x, _| if x < 20 { 0 } else { 255 });
        let out = only(|f| f.blur = 1.0).apply(&f);
        assert!(px(&out, 19, 10) > 0 && px(&out, 20, 10) < 255);
    }

    #[test]
    fn blur_keeps_a_flat_picture() {
        let f = frame(30, 30, |_, _| 90);
        let out = only(|f| f.blur = 1.0).apply(&f);
        assert!(out.data.chunks_exact(4).all(|p| p[0] == 90 && p[3] == 255));
    }

    #[test]
    fn pixelate_makes_blocks() {
        let f = frame(48, 48, |x, y| ((x * 5 + y * 3) % 256) as u8);
        let out = only(|f| f.pixelate = 1.0).apply(&f);
        assert_eq!(px(&out, 0, 0), px(&out, 1, 1));
    }

    #[test]
    fn sharpen_raises_contrast_at_an_edge() {
        let f = frame(40, 40, |x, _| if x < 20 { 80 } else { 160 });
        let out = only(|f| f.sharpen = 1.0).apply(&f);
        assert!(px(&out, 19, 10) < 80 && px(&out, 20, 10) > 160);
    }

    #[test]
    fn vignette_darkens_corners_not_centre() {
        let f = frame(40, 40, |_, _| 200);
        let out = only(|f| f.vignette = 1.0).apply(&f);
        assert_eq!(px(&out, 20, 20), 200);
        assert!(px(&out, 0, 0) < 100);
    }

    #[test]
    fn grain_is_repeatable_and_moves_with_time() {
        let f = frame(32, 32, |_, _| 128);
        let g = only(|f| f.grain = 1.0);
        assert_eq!(g.apply(&f).data, g.apply(&f).data);
        let later = RgbaFrame {
            pts_ms: 500,
            ..frame(32, 32, |_, _| 128)
        };
        assert_ne!(g.apply(&f).data, g.apply(&later).data);
        assert!(g.apply(&f).data.iter().any(|&v| v != 128));
    }
}
