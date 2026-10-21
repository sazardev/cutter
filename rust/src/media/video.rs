use std::collections::VecDeque;
use std::sync::Arc;

use anyhow::{Context, Result};
use ff::util::error::EAGAIN;
use ffmpeg_next as ff;

use super::probe::real_video_stream;
use super::{init, stream_rotation, ts_to_ms};

/// A decoded picture, scaled and rotated to its display size, tightly packed
/// RGBA.
pub struct RgbaFrame {
    pub width: u32,
    pub height: u32,
    pub pts_ms: i64,
    pub data: Vec<u8>,
}

/// What a scaler was built for: source format and size, target size.
type ScalerKey = (ff::format::Pixel, u32, u32, u32, u32);

/// How far back a reverse window reaches, and how many frames it keeps.
const REVERSE_WINDOW_MS: i64 = 1000;
const REVERSE_CACHE_FRAMES: usize = 64;
/// Memory the reverse window of one reader may hold.
const REVERSE_CACHE_BYTES: usize = 48 * 1024 * 1024;
/// How hard a reader decodes. Each frame thread keeps its own frames, so
/// threads cost memory as much as CPU.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DecodeLoad {
    /// Thumbnails and analysis: one thread.
    Light,
    /// Live preview: two threads, enough for 1080p in real time.
    Preview,
    /// Export: up to four threads.
    Export,
}

impl DecodeLoad {
    fn threads(self) -> usize {
        let cores = std::thread::available_parallelism().map_or(2, |n| n.get());
        match self {
            DecodeLoad::Light => 1,
            DecodeLoad::Preview => cores.clamp(1, 2),
            DecodeLoad::Export => cores.clamp(1, 4),
        }
    }
}
/// The longest a thumbnail decodes forward from its keyframe.
const NEAR_DECODE_MS: i64 = 1_500;
/// Forward jumps longer than this seek instead of decoding through.
const MAX_DECODE_AHEAD_MS: i64 = 1500;

/// Pictures of one file at any time, at any size. Decoding moves forward
/// cheaply; going backwards or jumping far seeks to the previous keyframe.
pub struct VideoReader {
    input: ff::format::context::Input,
    stream_index: usize,
    time_base: ff::Rational,
    start_ts: i64,
    decoder: ff::decoder::Video,
    rotation: i32,
    still: bool,
    eof_sent: bool,
    cur: Option<(i64, ff::frame::Video)>,
    next: Option<(i64, ff::frame::Video)>,
    scaler: Option<(ScalerKey, ff::software::scaling::Context)>,
    last_out: Option<Arc<RgbaFrame>>,
    reverse: VecDeque<Arc<RgbaFrame>>,
}

// SAFETY: the FFmpeg contexts are owned exclusively by the reader and only
// used from the thread that owns it at a time.
unsafe impl Send for VideoReader {}

impl VideoReader {
    /// Opens [path] for the live preview.
    #[cfg_attr(not(test), allow(dead_code))]
    pub fn open(path: &str) -> Result<Self> {
        Self::open_with(path, DecodeLoad::Preview)
    }

    pub fn open_with(path: &str, load: DecodeLoad) -> Result<Self> {
        init();
        let input = ff::format::input(&path).with_context(|| format!("cannot open {path}"))?;
        let stream = real_video_stream(&input).context("no video stream")?;
        let stream_index = stream.index();
        let time_base = stream.time_base();
        let start_ts = if stream.start_time() == ff::ffi::AV_NOPTS_VALUE {
            0
        } else {
            stream.start_time()
        };
        let rotation = stream_rotation(&stream);
        let mut ctx = ff::codec::Context::from_parameters(stream.parameters())?;
        ctx.set_threading(ff::codec::threading::Config {
            kind: if load == DecodeLoad::Light {
                ff::codec::threading::Type::None
            } else {
                ff::codec::threading::Type::Frame
            },
            count: load.threads(),
        });
        let mut decoder = ctx.decoder().video().context("unsupported video codec")?;
        if load == DecodeLoad::Light {
            // Thumbnails do not need the deblocking filter; skipping it makes
            // decoding noticeably cheaper.
            // SAFETY: the context is owned by this decoder and not yet in use.
            unsafe {
                (*decoder.as_mut_ptr()).skip_loop_filter = ff::ffi::AVDiscard::AVDISCARD_ALL;
            }
        }
        crate::diagnostics::video_decoder_opened(1);
        crate::diagnostics::info(format!(
            "video open {path}: {}x{} {:?}, rotation {rotation}",
            decoder.width(),
            decoder.height(),
            decoder.id()
        ));
        let demuxer = input.format().name().to_owned();
        let still =
            demuxer.contains("image2") || demuxer.ends_with("_pipe") || input.duration() <= 0;
        Ok(Self {
            input,
            stream_index,
            time_base,
            start_ts,
            decoder,
            rotation,
            still,
            eof_sent: false,
            cur: None,
            next: None,
            scaler: None,
            last_out: None,
            reverse: VecDeque::new(),
        })
    }

    /// Display size before any scaling, after rotation.
    pub fn display_size(&self) -> (u32, u32) {
        let (w, h) = (self.decoder.width(), self.decoder.height());
        if self.rotation % 180 == 0 {
            (w, h)
        } else {
            (h, w)
        }
    }

    /// The picture shown at [ms] of the source, at [width]x[height]. When
    /// [backwards] is set the reader keeps a window of recent frames so that
    /// playing in reverse does not seek for every frame.
    pub fn frame_at(
        &mut self,
        ms: i64,
        width: u32,
        height: u32,
        backwards: bool,
    ) -> Result<Option<Arc<RgbaFrame>>> {
        if self.still {
            return self.still_frame(width, height);
        }
        if backwards {
            return self.frame_backwards(ms, width, height);
        }
        self.advance_to(ms)?;
        let Some((pts, _)) = &self.cur else {
            return Ok(None);
        };
        let pts = *pts;
        if let Some(out) = &self.last_out {
            if out.pts_ms == pts && out.width == width && out.height == height {
                return Ok(Some(out.clone()));
            }
        }
        let frame = self.cur.take().unwrap();
        let out = Arc::new(self.convert(&frame.1, pts, width, height)?);
        self.cur = Some(frame);
        self.last_out = Some(out.clone());
        Ok(Some(out))
    }

    fn still_frame(&mut self, width: u32, height: u32) -> Result<Option<Arc<RgbaFrame>>> {
        if let Some(out) = &self.last_out {
            if out.width == width && out.height == height {
                return Ok(Some(out.clone()));
            }
        }
        if self.cur.is_none() {
            self.cur = self.decode_next()?;
        }
        let Some(frame) = self.cur.take() else {
            return Ok(None);
        };
        let out = Arc::new(self.convert(&frame.1, 0, width, height)?);
        self.cur = Some(frame);
        self.last_out = Some(out.clone());
        Ok(Some(out))
    }

    fn frame_backwards(
        &mut self,
        ms: i64,
        width: u32,
        height: u32,
    ) -> Result<Option<Arc<RgbaFrame>>> {
        let covered = matches!(
            (self.reverse.front(), self.reverse.back()),
            (Some(first), Some(last)) if first.pts_ms <= ms && ms <= last.pts_ms + 40
                && first.width == width && first.height == height
        );
        if !covered {
            self.clear_reverse();
            let from = (ms - REVERSE_WINDOW_MS).max(0);
            self.seek(from)?;
            while let Some((pts, frame)) = self.decode_next()? {
                if pts > ms {
                    self.next = Some((pts, frame));
                    break;
                }
                if pts >= from - 40 {
                    let out = Arc::new(self.convert(&frame, pts, width, height)?);
                    let bytes = out.data.len();
                    let cap = (REVERSE_CACHE_BYTES / bytes.max(1)).clamp(4, REVERSE_CACHE_FRAMES);
                    crate::diagnostics::cache_changed(bytes as i64);
                    self.reverse.push_back(out);
                    while self.reverse.len() > cap {
                        if let Some(old) = self.reverse.pop_front() {
                            crate::diagnostics::cache_changed(-(old.data.len() as i64));
                        }
                    }
                }
            }
        }
        Ok(self
            .reverse
            .iter()
            .rev()
            .find(|f| f.pts_ms <= ms)
            .or(self.reverse.front())
            .cloned())
    }

    /// A quick picture near [ms] for thumbnails: decoding walks forward from
    /// the keyframe the seek lands on, but for at most [NEAR_DECODE_MS], so a
    /// long keyframe interval cannot make one thumbnail expensive.
    ///
    /// [tolerance_ms] is how far before [ms] a picture may be: a strip
    /// zoomed out to 5 s per tile takes the keyframe as it is.
    pub fn keyframe_near(
        &mut self,
        ms: i64,
        tolerance_ms: i64,
        width: u32,
        height: u32,
    ) -> Result<Option<RgbaFrame>> {
        if self.still {
            return Ok(self.still_frame(width, height)?.map(|f| RgbaFrame {
                width: f.width,
                height: f.height,
                pts_ms: ms,
                data: f.data.clone(),
            }));
        }
        self.seek(ms)?;
        let Some((mut pts, mut frame)) = self.decode_next()? else {
            return Ok(None);
        };
        let first = pts;
        while ms - pts > tolerance_ms && pts - first < NEAR_DECODE_MS {
            match self.decode_next()? {
                Some((p, f)) if p <= ms => {
                    pts = p;
                    frame = f;
                }
                _ => break,
            }
        }
        self.next = None;
        self.cur = None;
        let out = self.convert(&frame, pts, width, height)?;
        Ok(Some(out))
    }

    fn clear_reverse(&mut self) {
        let bytes: usize = self.reverse.iter().map(|f| f.data.len()).sum();
        crate::diagnostics::cache_changed(-(bytes as i64));
        self.reverse.clear();
    }

    fn advance_to(&mut self, ms: i64) -> Result<()> {
        let needs_seek = match &self.cur {
            None => true,
            Some((pts, _)) => ms < *pts || ms > *pts + MAX_DECODE_AHEAD_MS,
        };
        if needs_seek {
            self.seek(ms)?;
            self.cur = self.decode_next()?;
        }
        loop {
            if self.next.is_none() {
                self.next = self.decode_next()?;
            }
            match &self.next {
                Some((pts, _)) if *pts <= ms => self.cur = self.next.take(),
                _ => return Ok(()),
            }
        }
    }

    fn seek(&mut self, ms: i64) -> Result<()> {
        let start_us = super::ts_to_ms(self.start_ts, self.time_base) * 1000;
        let target = (ms * 1000 + start_us).max(0);
        // Any keyframe at or before the target; decoding then walks forward.
        let _ = self.input.seek(target, ..target + 1);
        self.decoder.flush();
        self.eof_sent = false;
        self.cur = None;
        self.next = None;
        self.last_out = None;
        Ok(())
    }

    fn decode_next(&mut self) -> Result<Option<(i64, ff::frame::Video)>> {
        loop {
            let mut frame = ff::frame::Video::empty();
            match self.decoder.receive_frame(&mut frame) {
                Ok(()) => {
                    let ts = frame.timestamp().or(frame.pts()).unwrap_or(self.start_ts);
                    return Ok(Some((ts_to_ms(ts - self.start_ts, self.time_base), frame)));
                }
                Err(ff::Error::Eof) => return Ok(None),
                Err(ff::Error::Other { errno }) if errno == EAGAIN => {}
                Err(e) => return Err(e.into()),
            }
            if self.eof_sent {
                return Ok(None);
            }
            let mut packet = ff::Packet::empty();
            match packet.read(&mut self.input) {
                Ok(()) => {
                    if packet.stream() == self.stream_index {
                        // A corrupt packet loses one frame, not the clip.
                        let _ = self.decoder.send_packet(&packet);
                    }
                }
                Err(ff::Error::Eof) => {
                    self.decoder.send_eof()?;
                    self.eof_sent = true;
                }
                Err(e) => return Err(e.into()),
            }
        }
    }

    /// Scales [frame] to the display size [width]x[height] and rotates it.
    fn convert(
        &mut self,
        frame: &ff::frame::Video,
        pts_ms: i64,
        width: u32,
        height: u32,
    ) -> Result<RgbaFrame> {
        let (sw, sh) = if self.rotation % 180 == 0 {
            (width, height)
        } else {
            (height, width)
        };
        let key = (frame.format(), frame.width(), frame.height(), sw, sh);
        if self.scaler.as_ref().map(|(k, _)| *k) != Some(key) {
            let ctx = ff::software::scaling::Context::get(
                frame.format(),
                frame.width(),
                frame.height(),
                ff::format::Pixel::RGBA,
                sw,
                sh,
                ff::software::scaling::Flags::BILINEAR,
            )?;
            self.scaler = Some((key, ctx));
        }
        let mut scaled = ff::frame::Video::empty();
        self.scaler.as_mut().unwrap().1.run(frame, &mut scaled)?;
        let data = rotate_rgba(scaled.data(0), scaled.stride(0), sw, sh, self.rotation);
        Ok(RgbaFrame {
            width,
            height,
            pts_ms,
            data,
        })
    }
}

impl Drop for VideoReader {
    fn drop(&mut self) {
        self.clear_reverse();
        crate::diagnostics::video_decoder_opened(-1);
    }
}

/// Copies a strided RGBA picture into a tight buffer, rotating it clockwise by
/// [rotation] degrees.
pub fn rotate_rgba(src: &[u8], stride: usize, sw: u32, sh: u32, rotation: i32) -> Vec<u8> {
    let (sw, sh) = (sw as usize, sh as usize);
    let mut out = vec![0u8; sw * sh * 4];
    match rotation {
        0 => {
            for y in 0..sh {
                out[y * sw * 4..(y + 1) * sw * 4]
                    .copy_from_slice(&src[y * stride..y * stride + sw * 4]);
            }
        }
        _ => {
            let (dw, _dh) = if rotation == 180 { (sw, sh) } else { (sh, sw) };
            for sy in 0..sh {
                for sx in 0..sw {
                    let (dx, dy) = match rotation {
                        90 => (sh - 1 - sy, sx),
                        180 => (sw - 1 - sx, sh - 1 - sy),
                        _ => (sy, sw - 1 - sx),
                    };
                    let s = sy * stride + sx * 4;
                    let d = (dy * dw + dx) * 4;
                    out[d..d + 4].copy_from_slice(&src[s..s + 4]);
                }
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::VideoReader;
    use crate::test_support::fixtures;

    #[test]
    fn walks_forward_and_jumps_back() {
        let mut reader = VideoReader::open(&fixtures().video).unwrap();
        let mut last = -1;
        for t in (0..1000).step_by(33) {
            let frame = reader.frame_at(t, 320, 180, false).unwrap().unwrap();
            assert!(frame.pts_ms <= t && frame.pts_ms >= last);
            assert_eq!(frame.data.len(), 320 * 180 * 4);
            last = frame.pts_ms;
        }
        let back = reader.frame_at(200, 320, 180, false).unwrap().unwrap();
        assert!((back.pts_ms - 200).abs() <= 34, "{}", back.pts_ms);
    }

    #[test]
    fn plays_backwards_from_a_window() {
        let mut reader = VideoReader::open(&fixtures().video).unwrap();
        let mut previous = i64::MAX;
        for t in (500..2500).rev().step_by(33) {
            let frame = reader.frame_at(t, 160, 90, true).unwrap().unwrap();
            assert!(
                frame.pts_ms <= t && t - frame.pts_ms <= 34,
                "t {t} pts {}",
                frame.pts_ms
            );
            assert!(frame.pts_ms <= previous);
            previous = frame.pts_ms;
        }
    }

    #[test]
    fn rotates_to_the_display_size() {
        let mut reader = VideoReader::open(&fixtures().rotated).unwrap();
        assert_eq!(reader.display_size(), (360, 640));
        let frame = reader.frame_at(0, 180, 320, false).unwrap().unwrap();
        assert_eq!(
            (frame.width, frame.height, frame.data.len()),
            (180, 320, 180 * 320 * 4)
        );
    }

    #[test]
    fn reads_a_still_image() {
        let mut reader = VideoReader::open(&fixtures().image).unwrap();
        let a = reader.frame_at(0, 160, 120, false).unwrap().unwrap();
        let b = reader.frame_at(5000, 160, 120, false).unwrap().unwrap();
        assert!(std::sync::Arc::ptr_eq(&a, &b));
    }
}
