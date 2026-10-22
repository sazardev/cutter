//! Cutting the subject out of a picture: a small salient-object network
//! (U²-Net-P, Apache-2.0, run by tract, a pure Rust ONNX engine) draws a
//! mask, and the mask becomes the alpha channel of a PNG.

use std::fs::File;
use std::io::BufWriter;
use std::sync::OnceLock;

use anyhow::{anyhow, Context, Result};
use tract_onnx::prelude::*;

use crate::media::video::{DecodeLoad, RgbaFrame, VideoReader};

static MODEL: &[u8] = include_bytes!("../../assets/models/u2netp.onnx");

/// The side of the square the network looks at.
const NET: usize = 320;
const MEAN: [f32; 3] = [0.485, 0.456, 0.406];
const STD: [f32; 3] = [0.229, 0.224, 0.225];

/// The picture is cut at this long side at most; a bigger one is shrunk
/// first, which keeps memory and time bounded on a phone.
pub const MAX_SIDE: u32 = 2048;

type Model = std::sync::Arc<TypedRunnableModel>;

fn model() -> Result<&'static Model> {
    static MODEL_PLAN: OnceLock<Model> = OnceLock::new();
    if let Some(m) = MODEL_PLAN.get() {
        return Ok(m);
    }
    let plan = tract_onnx::onnx()
        .model_for_read(&mut std::io::Cursor::new(MODEL))
        .and_then(|m| {
            m.with_input_fact(0, f32::fact([1, 3, NET, NET]).into())?
                .into_optimized()?
                .into_runnable()
        })
        .map_err(|e| anyhow!("cannot load the background model: {e}"))?;
    Ok(MODEL_PLAN.get_or_init(|| plan))
}

/// The subject mask of [frame], one byte per pixel, 255 for the subject.
pub fn mask_of(frame: &RgbaFrame) -> Result<Vec<u8>> {
    let (w, h) = (frame.width as usize, frame.height as usize);
    let mut input = vec![0f32; 3 * NET * NET];
    for y in 0..NET {
        for x in 0..NET {
            let [r, g, b] = sample(
                frame,
                x as f32 / NET as f32 * w as f32,
                y as f32 / NET as f32 * h as f32,
            );
            for (c, v) in [r, g, b].into_iter().enumerate() {
                input[c * NET * NET + y * NET + x] = (v / 255.0 - MEAN[c]) / STD[c];
            }
        }
    }
    let tensor =
        Tensor::from_shape(&[1, 3, NET, NET], &input).map_err(|e| anyhow!("input tensor: {e}"))?;
    let outputs = model()?
        .run(tvec!(tensor.into()))
        .map_err(|e| anyhow!("background model failed: {e}"))?;
    let view = outputs[0]
        .to_plain_array_view::<f32>()
        .map_err(|e| anyhow!("model output: {e}"))?;
    let raw: Vec<f32> = view.iter().copied().collect();
    if raw.len() < NET * NET {
        return Err(anyhow!("the model returned {} values", raw.len()));
    }
    let (lo, hi) = raw[..NET * NET]
        .iter()
        .fold((f32::MAX, f32::MIN), |(lo, hi), &v| (lo.min(v), hi.max(v)));
    let span = (hi - lo).max(1e-6);
    let small: Vec<f32> = raw[..NET * NET].iter().map(|v| (v - lo) / span).collect();
    Ok(upscale_mask(&small, w, h))
}

/// Bilinear read of an RGB colour at fractional ([x], [y]).
fn sample(frame: &RgbaFrame, x: f32, y: f32) -> [f32; 3] {
    let (w, h) = (frame.width as usize, frame.height as usize);
    let (x, y) = (x.clamp(0.0, w as f32 - 1.0), y.clamp(0.0, h as f32 - 1.0));
    let (x0, y0) = (x as usize, y as usize);
    let (x1, y1) = ((x0 + 1).min(w - 1), (y0 + 1).min(h - 1));
    let (fx, fy) = (x - x0 as f32, y - y0 as f32);
    let at = |px: usize, py: usize, c: usize| f32::from(frame.data[(py * w + px) * 4 + c]);
    let mut out = [0.0; 3];
    for (c, o) in out.iter_mut().enumerate() {
        let top = at(x0, y0, c) * (1.0 - fx) + at(x1, y0, c) * fx;
        let bottom = at(x0, y1, c) * (1.0 - fx) + at(x1, y1, c) * fx;
        *o = top * (1.0 - fy) + bottom * fy;
    }
    out
}

/// Stretches the NETxNET [small] mask (0.0..=1.0) to [w]x[h] bytes.
fn upscale_mask(small: &[f32], w: usize, h: usize) -> Vec<u8> {
    let mut out = vec![0u8; w * h];
    for y in 0..h {
        let fy = ((y as f32 + 0.5) / h as f32 * NET as f32 - 0.5).clamp(0.0, NET as f32 - 1.0);
        let (y0, y1) = (fy as usize, (fy as usize + 1).min(NET - 1));
        let ty = fy - y0 as f32;
        for x in 0..w {
            let fx = ((x as f32 + 0.5) / w as f32 * NET as f32 - 0.5).clamp(0.0, NET as f32 - 1.0);
            let (x0, x1) = (fx as usize, (fx as usize + 1).min(NET - 1));
            let tx = fx - x0 as f32;
            let top = small[y0 * NET + x0] * (1.0 - tx) + small[y0 * NET + x1] * tx;
            let bottom = small[y1 * NET + x0] * (1.0 - tx) + small[y1 * NET + x1] * tx;
            let v = top * (1.0 - ty) + bottom * ty;
            // Push the soft edge of the network towards solid so the cut
            // is clean but keeps a pixel or two of feathering.
            let v = ((v - 0.5) * 1.6 + 0.5).clamp(0.0, 1.0);
            out[y * w + x] = (v * 255.0).round() as u8;
        }
    }
    out
}

/// [frame] with [mask] as its alpha channel.
pub fn apply_mask(frame: &RgbaFrame, mask: &[u8]) -> RgbaFrame {
    let mut data = frame.data.clone();
    for (px, m) in data.chunks_exact_mut(4).zip(mask) {
        px[3] = ((u32::from(px[3]) * u32::from(*m)) / 255) as u8;
    }
    RgbaFrame {
        width: frame.width,
        height: frame.height,
        pts_ms: frame.pts_ms,
        data,
    }
}

/// Writes [frame] as a PNG with transparency.
pub fn write_png(frame: &RgbaFrame, path: &str) -> Result<()> {
    let file = File::create(path).with_context(|| format!("cannot create {path}"))?;
    let mut encoder = png::Encoder::new(BufWriter::new(file), frame.width, frame.height);
    encoder.set_color(png::ColorType::Rgba);
    encoder.set_depth(png::BitDepth::Eight);
    let mut writer = encoder.write_header()?;
    writer.write_image_data(&frame.data)?;
    Ok(())
}

/// Reads the picture at [input], cuts its subject out and writes it to
/// [output] as a PNG; returns the size written.
pub fn remove_background(input: &str, output: &str) -> Result<(u32, u32)> {
    let mut reader = VideoReader::open_with(input, DecodeLoad::Light)?;
    let (sw, sh) = reader.display_size();
    let shrink = (f64::from(MAX_SIDE) / f64::from(sw.max(sh).max(1))).min(1.0);
    let (w, h) = (
        ((f64::from(sw) * shrink).round() as u32).max(2) & !1,
        ((f64::from(sh) * shrink).round() as u32).max(2) & !1,
    );
    let frame = reader
        .frame_at(0, w, h, false)?
        .ok_or_else(|| anyhow!("{input} has no picture"))?;
    let mask = mask_of(&frame)?;
    write_png(&apply_mask(&frame, &mask), output)?;
    Ok((frame.width, frame.height))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame(w: u32, h: u32, f: impl Fn(u32, u32) -> [u8; 3]) -> RgbaFrame {
        let mut data = Vec::new();
        for y in 0..h {
            for x in 0..w {
                let [r, g, b] = f(x, y);
                data.extend_from_slice(&[r, g, b, 255]);
            }
        }
        RgbaFrame {
            width: w,
            height: h,
            pts_ms: 0,
            data,
        }
    }

    #[test]
    fn the_mask_becomes_the_alpha_channel() {
        let f = frame(2, 1, |_, _| [10, 20, 30]);
        let out = apply_mask(&f, &[255, 0]);
        assert_eq!(out.data, vec![10, 20, 30, 255, 10, 20, 30, 0]);
    }

    #[test]
    fn a_flat_mask_stays_flat_when_stretched() {
        let small = vec![1.0; NET * NET];
        assert!(upscale_mask(&small, 37, 21).iter().all(|&v| v == 255));
        let none = vec![0.0; NET * NET];
        assert!(upscale_mask(&none, 37, 21).iter().all(|&v| v == 0));
    }

    #[test]
    fn a_png_round_trips_with_its_transparency() {
        let dir = std::env::temp_dir().join(format!("cutter-bg-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("cut.png");
        let mut f = frame(4, 4, |x, _| [x as u8 * 40, 0, 0]);
        f.data[3] = 0;
        write_png(&f, path.to_str().unwrap()).unwrap();

        let decoder = png::Decoder::new(File::open(&path).unwrap());
        let mut reader = decoder.read_info().unwrap();
        let mut buf = vec![0; reader.output_buffer_size()];
        let info = reader.next_frame(&mut buf).unwrap();
        assert_eq!((info.width, info.height), (4, 4));
        assert_eq!(buf[3], 0);
        assert_eq!(buf[7], 255);
        std::fs::remove_dir_all(dir).unwrap();
    }

    /// The network keeps a bright subject on a dark background and removes
    /// the background. Needs the model run, so it is slower than the rest.
    #[test]
    fn the_network_keeps_a_bright_blob_and_drops_a_dark_field() {
        let f = frame(256, 256, |x, y| {
            let (dx, dy) = (x as f32 - 128.0, y as f32 - 128.0);
            if dx * dx + dy * dy < 70.0 * 70.0 {
                [235, 90, 60]
            } else {
                [20, 24, 30]
            }
        });
        let mask = mask_of(&f).unwrap();
        let centre = mask[128 * 256 + 128];
        let corner = mask[4 * 256 + 4];
        assert!(centre > 200, "centre {centre}");
        assert!(corner < 60, "corner {corner}");
    }
}
