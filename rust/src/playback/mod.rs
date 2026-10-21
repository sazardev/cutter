//! The live preview: a render thread that composes the frame for the current
//! instant and an audio thread that mixes ahead of the device, both driven by
//! one clock.

mod audio_out;
pub mod clock;
pub mod texture;

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use parking_lot::{Condvar, Mutex};

use self::clock::Clock;
use crate::api::types::{PlaybackState, Timeline};
use crate::render::compositor::{fit, Compositor};

/// Receives each finished preview frame (tightly packed RGBA).
pub type FrameSink = Box<dyn Fn(Arc<Vec<u8>>, u32, u32) + Send + Sync>;
/// Receives the position while playing and after every seek.
pub type EventSink = Box<dyn Fn(PlaybackState) + Send + Sync>;

/// The longest side of the preview picture; the canvas is scaled down to it.
const MAX_PREVIEW_SIDE: u32 = 1280;
/// Position events are sent at most this often while playing.
const EVENT_INTERVAL: Duration = Duration::from_millis(33);

pub(crate) struct State {
    pub timeline: Arc<Timeline>,
    pub clock: Clock,
    pub looping: bool,
    pub dirty: bool,
    pub shutdown: bool,
    /// Bounding box the preview is drawn into, in physical pixels.
    pub bounds: (u32, u32),
}

pub(crate) struct Shared {
    pub state: Mutex<State>,
    pub wake: Condvar,
    /// Bumped on every seek, play, pause and edit: audio mixed before it is
    /// stale.
    pub generation: Arc<AtomicU64>,
}

impl Shared {
    fn touch(&self, state: &mut State) {
        state.dirty = true;
        self.generation.fetch_add(1, Ordering::AcqRel);
        self.wake.notify_all();
    }
}

/// One running preview. Dropping it stops both threads.
pub struct Session {
    shared: Arc<Shared>,
    threads: Vec<JoinHandle<()>>,
}

impl Session {
    pub fn start(frames: FrameSink, events: EventSink) -> Self {
        let shared = Arc::new(Shared {
            state: Mutex::new(State {
                timeline: Arc::new(Timeline {
                    width: 1080,
                    height: 1920,
                    fps: 30,
                    layers: vec![],
                }),
                clock: Clock::paused_at(0),
                looping: false,
                dirty: true,
                shutdown: false,
                bounds: (360, 640),
            }),
            wake: Condvar::new(),
            generation: Arc::new(AtomicU64::new(0)),
        });
        let render = {
            let shared = shared.clone();
            std::thread::Builder::new()
                .name("cutter-render".into())
                .spawn(move || render_loop(&shared, &frames, &events))
                .expect("cannot spawn the render thread")
        };
        let audio = audio_out::spawn(shared.clone());
        Self {
            shared,
            threads: vec![render, audio],
        }
    }

    pub fn set_timeline(&self, timeline: Timeline) {
        let mut state = self.shared.state.lock();
        let position = state.clock.now_ms();
        state.timeline = Arc::new(timeline);
        if state.clock.is_running() {
            state.clock = Clock::playing_from(position);
        }
        self.shared.touch(&mut state);
    }

    pub fn set_bounds(&self, width: u32, height: u32) {
        let mut state = self.shared.state.lock();
        state.bounds = (width.max(2), height.max(2));
        self.shared.touch(&mut state);
    }

    pub fn seek(&self, ms: i64) {
        let mut state = self.shared.state.lock();
        let ms = ms.clamp(0, state.timeline.duration_ms());
        state.clock = if state.clock.is_running() {
            Clock::playing_from(ms)
        } else {
            Clock::paused_at(ms)
        };
        self.shared.touch(&mut state);
    }

    pub fn play(&self) {
        let mut state = self.shared.state.lock();
        let duration = state.timeline.duration_ms();
        let mut from = state.clock.now_ms();
        if from >= duration {
            from = 0;
        }
        state.clock = Clock::playing_from(from);
        self.shared.touch(&mut state);
    }

    pub fn pause(&self) {
        let mut state = self.shared.state.lock();
        state.clock = Clock::paused_at(state.clock.now_ms());
        self.shared.touch(&mut state);
    }

    pub fn set_looping(&self, looping: bool) {
        self.shared.state.lock().looping = looping;
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        {
            let mut state = self.shared.state.lock();
            state.shutdown = true;
            self.shared.wake.notify_all();
        }
        for thread in self.threads.drain(..) {
            let _ = thread.join();
        }
    }
}

/// The size of the preview picture: the canvas fitted in [bounds], capped.
pub fn preview_size(timeline: &Timeline, bounds: (u32, u32)) -> (u32, u32) {
    let (_, _, w, h) = fit(
        timeline.width.max(2),
        timeline.height.max(2),
        bounds.0,
        bounds.1,
    );
    let scale = (f64::from(MAX_PREVIEW_SIDE) / f64::from(w.max(h))).min(1.0);
    (
        ((f64::from(w) * scale) as u32).max(2) & !1,
        ((f64::from(h) * scale) as u32).max(2) & !1,
    )
}

/// The preview resolution follows the cost of the frames while playing: it
/// drops when frames come close to their budget and climbs back when there
/// is room, so playback stays fluid with many layers. Paused frames and
/// exports are always drawn at full size.
#[derive(Debug, Clone, Copy)]
pub struct AdaptiveQuality {
    pub scale: f64,
    smoothed_ms: f64,
}

impl Default for AdaptiveQuality {
    fn default() -> Self {
        Self {
            scale: 1.0,
            smoothed_ms: 0.0,
        }
    }
}

impl AdaptiveQuality {
    const MIN_SCALE: f64 = 0.5;

    pub fn observe(&mut self, took_ms: f64, budget_ms: f64) {
        self.smoothed_ms = if self.smoothed_ms == 0.0 {
            took_ms
        } else {
            self.smoothed_ms * 0.8 + took_ms * 0.2
        };
        let before = self.scale;
        if self.smoothed_ms > budget_ms * 0.75 {
            self.scale = (self.scale * 0.85).max(Self::MIN_SCALE);
            self.smoothed_ms *= 0.85 * 0.85;
        } else if self.smoothed_ms < budget_ms * 0.3 {
            self.scale = (self.scale * 1.05).min(1.0);
        }
        if (before - self.scale).abs() > 0.1 || (self.scale < 1.0 && before == 1.0) {
            crate::diagnostics::info(format!(
                "preview quality {:.0}% (frames {:.1} ms of {:.1} ms)",
                self.scale * 100.0,
                self.smoothed_ms,
                budget_ms
            ));
        }
        crate::diagnostics::preview_scale(self.scale);
    }
}

fn render_loop(shared: &Shared, frames: &FrameSink, events: &EventSink) {
    // Two drawing threads at most: the UI, audio and decoders need the rest.
    let mut compositor = Compositor::with_threads(2);
    let mut timeline_seen: Option<Arc<Timeline>> = None;
    // Buffers rotate: the texture may still read the last one published.
    let mut pool: Vec<Arc<Vec<u8>>> = Vec::new();
    let mut last_event = Instant::now() - EVENT_INTERVAL;
    let mut quality = AdaptiveQuality::default();
    loop {
        let (timeline, clock, bounds) = {
            let mut state = shared.state.lock();
            loop {
                if state.shutdown {
                    return;
                }
                if state.dirty || state.clock.is_running() {
                    break;
                }
                shared.wake.wait(&mut state);
            }
            state.dirty = false;
            let duration = state.timeline.duration_ms();
            if state.clock.is_running() && state.clock.now_ms() >= duration {
                state.clock = if state.looping && duration > 0 {
                    Clock::playing_from(0)
                } else {
                    Clock::paused_at(duration)
                };
                shared.generation.fetch_add(1, Ordering::AcqRel);
                shared.wake.notify_all();
            }
            (state.timeline.clone(), state.clock, state.bounds)
        };
        if timeline_seen
            .as_ref()
            .is_none_or(|t| !Arc::ptr_eq(t, &timeline))
        {
            compositor.retain(&timeline);
            timeline_seen = Some(timeline.clone());
        }

        let started = Instant::now();
        let t = clock.now_ms();
        // At the very end no clip is active any more: show the last frame
        // rather than black.
        let shown = t.min((timeline.duration_ms() - 1).max(0));
        let (fw, fh) = preview_size(&timeline, bounds);
        let w = ((f64::from(fw) * quality.scale) as u32).max(2) & !1;
        let h = ((f64::from(fh) * quality.scale) as u32).max(2) & !1;
        let free = pool.iter().position(|b| Arc::strong_count(b) == 1);
        let mut buffer = free
            .and_then(|i| Arc::try_unwrap(pool.swap_remove(i)).ok())
            .unwrap_or_default();
        // A bug in one frame must not take the preview down: log it and
        // keep going with the next one.
        let rendered = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            compositor.render(&timeline, shown, w, h, &mut buffer);
        }));
        if rendered.is_err() {
            crate::diagnostics::error(format!("preview frame at {shown} ms panicked"));
            compositor = Compositor::with_threads(2);
            timeline_seen = None;
            continue;
        }
        let budget_ms = 1000.0 / f64::from(timeline.fps.clamp(1, 120));
        let took_ms = started.elapsed().as_secs_f64() * 1000.0;
        crate::diagnostics::frame_rendered(took_ms, budget_ms);
        if clock.is_running() {
            quality.observe(took_ms, budget_ms);
        }
        let buffer = Arc::new(buffer);
        frames(buffer.clone(), w, h);
        pool.push(buffer);
        if pool.len() > 3 {
            pool.remove(0);
        }

        let playing = clock.is_running();
        if !playing || last_event.elapsed() >= EVENT_INTERVAL {
            events(PlaybackState {
                position_ms: t,
                playing,
            });
            last_event = Instant::now();
        }
        if playing {
            let frame = Duration::from_millis(1000 / u64::from(timeline.fps.clamp(1, 120)));
            if let Some(rest) = frame.checked_sub(started.elapsed()) {
                std::thread::sleep(rest);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicI64, AtomicUsize, Ordering};
    use std::sync::Arc;
    use std::time::Duration;

    use super::{preview_size, Session};
    use crate::api::types::{EngineMediaKind, Timeline};
    use crate::test_support::{clip, fixtures, layer, vertical};

    #[test]
    fn the_preview_keeps_the_canvas_shape() {
        let t = Timeline {
            width: 1080,
            height: 1920,
            fps: 30,
            layers: vec![],
        };
        assert_eq!(preview_size(&t, (800, 800)), (450, 800));
        assert_eq!(preview_size(&t, (4000, 4000)).1, 1280);
    }

    #[test]
    fn plays_seeks_and_stops_at_the_end() {
        let f = fixtures();
        let frames = Arc::new(AtomicUsize::new(0));
        let position = Arc::new(AtomicI64::new(-1));
        let (fc, pc) = (frames.clone(), position.clone());
        let session = Session::start(
            Box::new(move |data, w, h| {
                assert_eq!(data.len(), (w * h * 4) as usize);
                fc.fetch_add(1, Ordering::SeqCst);
            }),
            Box::new(move |state| pc.store(state.position_ms, Ordering::SeqCst)),
        );
        session.set_timeline(vertical(vec![layer(
            EngineMediaKind::Video,
            vec![clip(&f.video, EngineMediaKind::Video, 0, 0, 600)],
        )]));
        session.seek(300);
        std::thread::sleep(Duration::from_millis(150));
        assert_eq!(position.load(Ordering::SeqCst), 300);

        let before = frames.load(Ordering::SeqCst);
        session.play();
        std::thread::sleep(Duration::from_millis(700));
        assert!(frames.load(Ordering::SeqCst) - before >= 5);
        // Past the end it pauses on the last instant.
        assert_eq!(position.load(Ordering::SeqCst), 600);
    }

    #[test]
    fn quality_drops_when_frames_are_slow_and_recovers() {
        let mut q = super::AdaptiveQuality::default();
        for _ in 0..10 {
            q.observe(30.0, 33.3);
        }
        assert!(q.scale < 0.8);
        assert!(q.scale >= 0.5);
        for _ in 0..200 {
            q.observe(2.0, 33.3);
        }
        assert!((q.scale - 1.0).abs() < 1e-9);
    }
}
