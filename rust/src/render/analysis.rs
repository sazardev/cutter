//! Measuring pictures to suggest automatic adjustments.

use anyhow::Result;

use crate::api::types::SuggestedAdjustments;
use crate::media::video::{DecodeLoad, VideoReader};

/// Frames measured per clip, spread over its range.
const SAMPLES: i64 = 5;
/// Size frames are measured at: enough for statistics, cheap to decode.
const MEASURE_SIDE: u32 = 160;

/// Luma mean and spread, and mean saturation, of RGBA pixels, each 0..1.
pub fn measure(rgba: &[u8]) -> (f64, f64, f64) {
    let n = (rgba.len() / 4).max(1) as f64;
    let (mut sum, mut sum_sq, mut sat) = (0.0, 0.0, 0.0);
    for px in rgba.chunks_exact(4) {
        let (r, g, b) = (f64::from(px[0]), f64::from(px[1]), f64::from(px[2]));
        let y = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
        sum += y;
        sum_sq += y * y;
        let (max, min) = (r.max(g).max(b), r.min(g).min(b));
        sat += if max > 0.0 { (max - min) / max } else { 0.0 };
    }
    let mean = sum / n;
    let spread = (sum_sq / n - mean * mean).max(0.0).sqrt();
    (mean, spread, sat / n)
}

/// The adjustments that move measured values towards balanced targets,
/// gently: a picture already balanced gets almost nothing.
pub fn suggestion(mean: f64, spread: f64, saturation: f64) -> SuggestedAdjustments {
    const TARGET_MEAN: f64 = 0.48;
    const TARGET_SPREAD: f64 = 0.22;
    const TARGET_SAT: f64 = 0.35;
    // Gentle on purpose: half of the distance to the target at most, and
    // small limits, so a deliberately dark or muted picture is nudged, not
    // repainted.
    let brightness = ((TARGET_MEAN - mean) * 0.5).clamp(-0.2, 0.2);
    let contrast = if spread > 0.0 {
        ((TARGET_SPREAD / spread - 1.0) * 0.25).clamp(-0.15, 0.25)
    } else {
        0.0
    };
    let saturation = ((TARGET_SAT - saturation) * 0.5).clamp(-0.15, 0.2);
    let round = |v: f64| ((v * 40.0).round() / 40.0) as f32;
    SuggestedAdjustments {
        brightness: round(brightness),
        contrast: round(contrast),
        saturation: round(saturation),
    }
}

pub fn suggest(path: &str, from_ms: i64, to_ms: i64) -> Result<SuggestedAdjustments> {
    let mut reader = VideoReader::open_with(path, DecodeLoad::Light)?;
    let (sw, sh) = reader.display_size();
    let scale = f64::from(MEASURE_SIDE) / f64::from(sw.max(sh).max(1));
    let (w, h) = (
        ((f64::from(sw) * scale) as u32).max(2),
        ((f64::from(sh) * scale) as u32).max(2),
    );
    let span = (to_ms - from_ms).max(1);
    let (mut mean, mut spread, mut sat, mut n) = (0.0, 0.0, 0.0, 0.0);
    for i in 0..SAMPLES {
        let t = from_ms + span * (2 * i + 1) / (2 * SAMPLES);
        if let Some(frame) = reader.keyframe_near(t, span / SAMPLES, w, h)? {
            let (m, s, c) = measure(&frame.data);
            mean += m;
            spread += s;
            sat += c;
            n += 1.0;
        }
    }
    if n == 0.0 {
        return Ok(SuggestedAdjustments {
            brightness: 0.0,
            contrast: 0.0,
            saturation: 0.0,
        });
    }
    Ok(suggestion(mean / n, spread / n, sat / n))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_dark_flat_picture_gets_brighter_and_more_contrasted() {
        let s = suggestion(0.15, 0.05, 0.1);
        assert!(s.brightness > 0.1 && s.contrast > 0.1 && s.saturation > 0.05);
    }

    #[test]
    fn suggestions_stay_gentle() {
        let s = suggestion(0.0, 0.01, 0.0);
        assert!(s.brightness <= 0.2 && s.contrast <= 0.25 && s.saturation <= 0.2);
    }

    #[test]
    fn a_balanced_picture_gets_almost_nothing() {
        let s = suggestion(0.48, 0.22, 0.35);
        assert_eq!((s.brightness, s.contrast, s.saturation), (0.0, 0.0, 0.0));
    }

    #[test]
    fn measures_real_frames() {
        let f = crate::test_support::fixtures();
        let s = suggest(&f.video, 0, 3000).unwrap();
        assert!(s.brightness.abs() <= 0.4 && s.contrast.abs() <= 0.4);
    }
}
