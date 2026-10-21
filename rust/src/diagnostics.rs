//! Counters and a short log of what the engine did, so a slow frame or a
//! file that will not open can be traced from the app.

use std::collections::VecDeque;
use std::sync::atomic::{AtomicI64, AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use parking_lot::Mutex;

use crate::api::types::EngineDiagnostics;

const LOG_LINES: usize = 200;
/// Composition times kept for the mean and worst values.
const RENDER_WINDOW: usize = 120;

static FRAMES: AtomicU64 = AtomicU64::new(0);
static LATE: AtomicU64 = AtomicU64::new(0);
static VIDEO_DECODERS: AtomicI64 = AtomicI64::new(0);
static AUDIO_DECODERS: AtomicI64 = AtomicI64::new(0);
static CACHE_BYTES: AtomicI64 = AtomicI64::new(0);
static RENDER_TIMES: Mutex<VecDeque<f64>> = Mutex::new(VecDeque::new());
static LOG: Mutex<VecDeque<String>> = Mutex::new(VecDeque::new());
/// Preview resolution in per mille of full size.
static PREVIEW_SCALE: AtomicI64 = AtomicI64::new(1000);

#[derive(Clone, Copy)]
pub enum Level {
    Info,
    Warn,
    Error,
}

/// Records one log line; it also goes to stderr, which `flutter run` shows.
pub fn log(level: Level, message: impl AsRef<str>) {
    let tag = match level {
        Level::Info => "I",
        Level::Warn => "W",
        Level::Error => "E",
    };
    let ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() % 86_400_000)
        .unwrap_or(0);
    let (h, m, s, milli) = (ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000);
    let line = format!("{h:02}:{m:02}:{s:02}.{milli:03} {tag} {}", message.as_ref());
    eprintln!("cutter-engine {line}");
    let mut log = LOG.lock();
    log.push_back(line);
    while log.len() > LOG_LINES {
        log.pop_front();
    }
}

pub fn info(message: impl AsRef<str>) {
    log(Level::Info, message);
}

pub fn warn(message: impl AsRef<str>) {
    log(Level::Warn, message);
}

pub fn error(message: impl AsRef<str>) {
    log(Level::Error, message);
}

/// Records how long one preview frame took and whether it missed its slot.
pub fn frame_rendered(ms: f64, budget_ms: f64) {
    FRAMES.fetch_add(1, Ordering::Relaxed);
    if ms > budget_ms {
        LATE.fetch_add(1, Ordering::Relaxed);
    }
    let mut times = RENDER_TIMES.lock();
    times.push_back(ms);
    while times.len() > RENDER_WINDOW {
        times.pop_front();
    }
}

pub fn video_decoder_opened(delta: i64) {
    VIDEO_DECODERS.fetch_add(delta, Ordering::Relaxed);
}

pub fn audio_decoder_opened(delta: i64) {
    AUDIO_DECODERS.fetch_add(delta, Ordering::Relaxed);
}

pub fn cache_changed(delta_bytes: i64) {
    CACHE_BYTES.fetch_add(delta_bytes, Ordering::Relaxed);
}

pub fn preview_scale(scale: f64) {
    PREVIEW_SCALE.store((scale * 1000.0) as i64, Ordering::Relaxed);
}

pub fn snapshot() -> EngineDiagnostics {
    let times = RENDER_TIMES.lock();
    let avg = if times.is_empty() {
        0.0
    } else {
        times.iter().sum::<f64>() / times.len() as f64
    };
    let max = times.iter().copied().fold(0.0, f64::max);
    EngineDiagnostics {
        frames_rendered: FRAMES.load(Ordering::Relaxed),
        avg_render_ms: avg,
        max_render_ms: max,
        late_frames: LATE.load(Ordering::Relaxed),
        open_video_decoders: VIDEO_DECODERS.load(Ordering::Relaxed).max(0) as u32,
        open_audio_decoders: AUDIO_DECODERS.load(Ordering::Relaxed).max(0) as u32,
        cache_bytes: CACHE_BYTES.load(Ordering::Relaxed).max(0) as u64,
        preview_scale: PREVIEW_SCALE.load(Ordering::Relaxed) as f64 / 1000.0,
        log: LOG.lock().iter().cloned().collect(),
    }
}
