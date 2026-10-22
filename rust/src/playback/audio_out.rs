use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use crossbeam_channel::{bounded, Receiver, SendTimeoutError};

use super::Shared;
use crate::media::audio::{CHANNELS, SAMPLE_RATE};
use crate::render::mixer::Mixer;

const BLOCK_FRAMES: usize = 1024;
/// About 128 ms of sound mixed ahead of the device.
const QUEUED_BLOCKS: usize = 6;
/// How long to wait before trying the audio device again after it failed
/// or vanished (headphones unplugged, Bluetooth switched, app resumed).
const RETRY_EVERY: Duration = Duration::from_secs(1);

struct Block {
    generation: u64,
    data: Vec<f32>,
}

/// Starts the thread that mixes the timeline and feeds the audio device.
/// Without a usable device the preview stays silent and keeps playing.
pub fn spawn(shared: Arc<Shared>) -> JoinHandle<()> {
    std::thread::Builder::new()
        .name("cutter-audio".into())
        .spawn(move || run(shared))
        .expect("cannot spawn the audio thread")
}

fn run(shared: Arc<Shared>) {
    let (tx, rx) = bounded::<Block>(QUEUED_BLOCKS);
    // The stream must live on this thread: it is not Send on every platform.
    let failed = Arc::new(AtomicBool::new(false));
    let mut stream = open_stream(rx.clone(), shared.generation.clone(), failed.clone());
    let mut last_try = Instant::now();
    let mut reported = stream.is_some();
    if reported {
        crate::diagnostics::info("audio output open");
    } else {
        crate::diagnostics::warn("no audio output device: trying again while playing");
    }
    let mut mixer = Mixer::default();
    let mut generation = u64::MAX;
    let mut position = 0i64;
    let mut pending: Option<Block> = None;
    loop {
        let (timeline, clock, current) = {
            let mut state = shared.state.lock();
            if state.shutdown {
                return;
            }
            if !state.clock.is_running() {
                shared.wake.wait_for(&mut state, Duration::from_millis(100));
                continue;
            }
            (
                state.timeline.clone(),
                state.clock,
                shared.generation.load(Ordering::Acquire),
            )
        };
        // A device that was missing, or whose stream died, is tried again
        // while playing, so sound comes back without restarting the app.
        if (stream.is_none() || failed.load(Ordering::Relaxed))
            && last_try.elapsed() >= RETRY_EVERY
        {
            last_try = Instant::now();
            failed.store(false, Ordering::Relaxed);
            drop(stream.take());
            stream = open_stream(rx.clone(), shared.generation.clone(), failed.clone());
            if stream.is_some() != reported {
                reported = stream.is_some();
                if reported {
                    crate::diagnostics::info("audio output open again");
                } else {
                    crate::diagnostics::warn("audio output lost: trying again while playing");
                }
            }
        }
        if current != generation {
            generation = current;
            position = clock.now_frames();
            pending = None;
            mixer.retain(&timeline);
        }
        let block = pending.take().unwrap_or_else(|| {
            let mut data = vec![0f32; BLOCK_FRAMES * CHANNELS];
            mixer.mix(&timeline, position, &mut data);
            position += BLOCK_FRAMES as i64;
            Block { generation, data }
        });
        match tx.send_timeout(block, Duration::from_millis(40)) {
            Ok(()) => {}
            Err(SendTimeoutError::Timeout(block)) => pending = Some(block),
            Err(SendTimeoutError::Disconnected(_)) => {
                // No device: pace the loop as if one were consuming.
                std::thread::sleep(Duration::from_millis(
                    (BLOCK_FRAMES as u64 * 1000) / u64::from(SAMPLE_RATE),
                ));
            }
        }
    }
}

/// Reads queued blocks at the device rate, dropping blocks mixed before the
/// last seek, play or edit.
struct Feed {
    rx: Receiver<Block>,
    generation: Arc<AtomicU64>,
    block: Option<Block>,
    /// Position inside the current block, in source frames, fractional when
    /// the device rate is not 48 kHz.
    pos: f64,
    step: f64,
}

impl Feed {
    fn next_frame(&mut self) -> (f32, f32) {
        loop {
            if let Some(block) = &self.block {
                let frames = block.data.len() / CHANNELS;
                let i = self.pos as usize;
                if block.generation == self.generation.load(Ordering::Relaxed) && i < frames {
                    let j = (i + 1).min(frames - 1);
                    let f = (self.pos - i as f64) as f32;
                    let l = block.data[i * 2] * (1.0 - f) + block.data[j * 2] * f;
                    let r = block.data[i * 2 + 1] * (1.0 - f) + block.data[j * 2 + 1] * f;
                    self.pos += self.step;
                    return (l, r);
                }
                self.pos -= frames as f64;
                if self.pos < 0.0 {
                    self.pos = 0.0;
                }
            }
            match self.rx.try_recv() {
                Ok(block) => self.block = Some(block),
                Err(_) => {
                    self.block = None;
                    self.pos = 0.0;
                    return (0.0, 0.0);
                }
            }
        }
    }
}

fn open_stream(
    rx: Receiver<Block>,
    generation: Arc<AtomicU64>,
    failed: Arc<AtomicBool>,
) -> Option<cpal::Stream> {
    let host = cpal::default_host();
    let device = host.default_output_device()?;
    let supported = device.default_output_config().ok()?;
    let format = supported.sample_format();
    crate::diagnostics::info(format!(
        "audio device {} at {} Hz, {} channels, {:?}",
        device
            .description()
            .map_or_else(|_| "unknown".to_string(), |d| d.to_string()),
        supported.sample_rate(),
        supported.channels(),
        format,
    ));
    let config: cpal::StreamConfig = supported.config();
    let channels = config.channels as usize;
    let mut feed = Feed {
        rx,
        generation,
        block: None,
        pos: 0.0,
        step: f64::from(SAMPLE_RATE) / f64::from(config.sample_rate),
    };
    let err = move |e| {
        crate::diagnostics::warn(format!("audio stream error: {e}"));
        failed.store(true, Ordering::Relaxed);
    };
    let stream = match format {
        cpal::SampleFormat::F32 => device.build_output_stream::<f32, _, _>(
            config,
            move |out, _| write(out, channels, &mut feed, |s| s),
            err,
            None,
        ),
        cpal::SampleFormat::I16 => device.build_output_stream::<i16, _, _>(
            config,
            move |out, _| {
                write(out, channels, &mut feed, |s| {
                    (s * f32::from(i16::MAX)) as i16
                })
            },
            err,
            None,
        ),
        cpal::SampleFormat::I32 => device.build_output_stream::<i32, _, _>(
            config,
            move |out, _| {
                write(out, channels, &mut feed, |s| {
                    (f64::from(s) * f64::from(i32::MAX)) as i32
                })
            },
            err,
            None,
        ),
        _ => return None,
    }
    .ok()?;
    stream.play().ok()?;
    Some(stream)
}

fn write<T: Copy>(out: &mut [T], channels: usize, feed: &mut Feed, convert: impl Fn(f32) -> T) {
    for frame in out.chunks_exact_mut(channels.max(1)) {
        let (l, r) = feed.next_frame();
        for (c, sample) in frame.iter_mut().enumerate() {
            *sample = convert(if c % 2 == 0 { l } else { r });
        }
    }
}
