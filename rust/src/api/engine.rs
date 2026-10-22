//! The functions and objects Flutter calls. Every blocking call runs on the
//! bridge's worker pool; the `sync` ones only flip state and return at once.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use anyhow::{anyhow, Result};
use flutter_rust_bridge::frb;
use irondash_texture::{BoxedPixelData, PayloadProvider, SendableTexture, Texture};
use parking_lot::Mutex;

use super::types::{
    EngineDiagnostics, ExportEvent, ExportSettings, ExportStage, MediaInfo, PlaybackState,
    SuggestedAdjustments, TextSize, TextSpec, Thumbnail, Timeline,
};
use crate::frb_generated::StreamSink;
use crate::media::video::{DecodeLoad, VideoReader};
use crate::playback::texture::LatestFrame;
use crate::playback::Session;

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
    crate::media::init();
    #[cfg(target_os = "android")]
    crate::android::init();
}

/// Counters and recent log lines of the engine.
#[frb(sync)]
pub fn engine_diagnostics() -> EngineDiagnostics {
    crate::diagnostics::snapshot()
}

/// The size of the picture [spec] draws on a canvas [canvas_height] pixels
/// tall, so the editor can frame a text without drawing it.
#[frb(sync)]
pub fn measure_text(spec: TextSpec, canvas_height: u32) -> TextSize {
    let (width, height) = crate::render::text::measure(&spec, canvas_height);
    TextSize { width, height }
}

/// Describes the file at [path]; fails when it cannot be played.
pub fn probe_media(path: String) -> Result<MediaInfo> {
    crate::media::probe::probe(&path).inspect_err(|e| {
        crate::diagnostics::warn(format!("probe {path}: {e:#}"));
    })
}

/// Decoders kept between thumbnail requests, the most recent last.
static THUMB_READERS: Mutex<Vec<(String, VideoReader)>> = Mutex::new(Vec::new());
const THUMB_READER_CACHE: usize = 2;

/// Pictures of [path] near each of [times_ms], [height] pixels tall. Each
/// comes from the closest keyframe, so a strip of a long video costs one
/// seek per picture instead of decoding through it.
pub fn thumbnails(
    path: String,
    times_ms: Vec<i64>,
    height: u32,
    tolerance_ms: i64,
) -> Result<Vec<Thumbnail>> {
    let cached = {
        let mut cache = THUMB_READERS.lock();
        cache
            .iter()
            .position(|(p, _)| p == &path)
            .map(|i| cache.remove(i).1)
    };
    let mut reader = match cached {
        Some(reader) => reader,
        None => VideoReader::open_with(&path, DecodeLoad::Light)?,
    };
    let (sw, sh) = reader.display_size();
    let height = height.max(2) & !1;
    let width = ((u64::from(sw) * u64::from(height) / u64::from(sh.max(1))) as u32).max(2) & !1;
    let mut times = times_ms;
    times.sort_unstable();
    let mut out = Vec::with_capacity(times.len());
    for t in times {
        if let Some(frame) = reader.keyframe_near(t, tolerance_ms.max(0), width, height)? {
            out.push(Thumbnail {
                time_ms: t,
                width: frame.width,
                height: frame.height,
                rgba: frame.data,
            });
        }
    }
    let mut cache = THUMB_READERS.lock();
    cache.push((path, reader));
    while cache.len() > THUMB_READER_CACHE {
        cache.remove(0);
    }
    Ok(out)
}

/// Peak loudness of [path] in [buckets] slices, each 0.0 to 1.0.
pub fn waveform(path: String, buckets: u32) -> Result<Vec<f32>> {
    crate::media::audio::waveform(&path, buckets.max(1) as usize)
}

/// A running export that Flutter can cancel.
#[frb(opaque)]
pub struct ExportJob {
    cancelled: Arc<AtomicBool>,
}

impl ExportJob {
    #[frb(sync)]
    pub fn new() -> ExportJob {
        ExportJob {
            cancelled: Arc::new(AtomicBool::new(false)),
        }
    }

    #[frb(sync)]
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
    }

    /// Renders [timeline] to [path], reporting progress on [events]. The last
    /// event is `Done`, `Failed` or `Cancelled`.
    pub fn run(
        &self,
        timeline: Timeline,
        settings: ExportSettings,
        path: String,
        events: StreamSink<ExportEvent>,
    ) {
        let cancelled = self.cancelled.clone();
        let mut last = -1.0;
        let result = crate::export::export(&timeline, &settings, &path, |fraction| {
            if fraction - last >= 0.005 || fraction >= 1.0 {
                last = fraction;
                let _ = events.add(ExportEvent::running(fraction));
            }
            !cancelled.load(Ordering::Acquire)
        });
        let _ = events.add(match result {
            Ok(()) => ExportEvent::finished(ExportStage::Done, None),
            Err(e) if e.is::<crate::export::Cancelled>() => {
                ExportEvent::finished(ExportStage::Cancelled, None)
            }
            Err(e) => {
                crate::diagnostics::error(format!("export failed: {e:#}"));
                ExportEvent::finished(ExportStage::Failed, Some(format!("{e:#}")))
            }
        });
    }
}

/// The live preview of a timeline, drawn into a Flutter texture.
#[frb(opaque)]
pub struct PreviewPlayer {
    session: Option<Session>,
    texture: Option<Arc<SendableTexture<BoxedPixelData>>>,
    texture_id: i64,
    events: Arc<Mutex<Option<StreamSink<PlaybackState>>>>,
}

impl PreviewPlayer {
    /// Creates the texture in the Flutter engine [engine_handle] and starts
    /// the preview threads.
    pub fn create(engine_handle: i64) -> Result<PreviewPlayer> {
        let latest = Arc::new(LatestFrame::default());
        let (tx, rx) = std::sync::mpsc::channel();
        let provider: Arc<dyn PayloadProvider<BoxedPixelData>> = latest.clone();
        irondash_engine_context::EngineContext::perform_on_main_thread(move || {
            let made = Texture::new_with_provider(engine_handle, provider)
                .map(|t| (t.id(), t.into_sendable_texture()))
                .map_err(|e| format!("{e:?}"));
            let _ = tx.send(made);
        })
        .map_err(|e| anyhow!("{e:?}"))?;
        let (texture_id, texture) = rx
            .recv()?
            .map_err(|e| anyhow!("cannot create the preview texture: {e}"))?;

        let sink_texture = texture.clone();
        let events: Arc<Mutex<Option<StreamSink<PlaybackState>>>> = Arc::default();
        let events_out = events.clone();
        let session = Session::start(
            Box::new(move |data, width, height| {
                latest.set(data, width, height);
                sink_texture.mark_frame_available();
            }),
            Box::new(move |state| {
                if let Some(sink) = events_out.lock().as_ref() {
                    let _ = sink.add(state);
                }
            }),
        );
        Ok(PreviewPlayer {
            session: Some(session),
            texture: Some(texture),
            texture_id,
            events,
        })
    }

    /// The playback position while playing and after every seek or edit.
    pub fn events(&self, sink: StreamSink<PlaybackState>) {
        *self.events.lock() = Some(sink);
    }

    #[frb(sync, getter)]
    pub fn texture_id(&self) -> i64 {
        self.texture_id
    }

    #[frb(sync)]
    pub fn set_timeline(&self, timeline: Timeline) {
        if let Some(s) = &self.session {
            s.set_timeline(timeline);
        }
    }

    /// The box, in physical pixels, the preview is shown in.
    #[frb(sync)]
    pub fn set_bounds(&self, width: u32, height: u32) {
        if let Some(s) = &self.session {
            s.set_bounds(width, height);
        }
    }

    #[frb(sync)]
    pub fn seek(&self, position_ms: i64) {
        if let Some(s) = &self.session {
            s.seek(position_ms);
        }
    }

    #[frb(sync)]
    pub fn play(&self) {
        if let Some(s) = &self.session {
            s.play();
        }
    }

    #[frb(sync)]
    pub fn pause(&self) {
        if let Some(s) = &self.session {
            s.pause();
        }
    }

    #[frb(sync)]
    pub fn set_looping(&self, looping: bool) {
        if let Some(s) = &self.session {
            s.set_looping(looping);
        }
    }
}

impl Drop for PreviewPlayer {
    fn drop(&mut self) {
        // Stop the threads first so nothing touches the texture any more,
        // then release the texture on the thread that created it.
        drop(self.session.take());
        if let Some(texture) = self.texture.take() {
            let _ = irondash_engine_context::EngineContext::perform_on_main_thread(move || {
                drop(texture)
            });
        }
    }
}

/// Cuts the subject out of the picture at [input_path] and writes it to
/// [output_path] as a PNG with a transparent background; returns the width
/// and height written. A picture larger than 2048 px on its long side is
/// shrunk first.
pub fn remove_background(input_path: String, output_path: String) -> Result<(u32, u32)> {
    crate::render::background::remove_background(&input_path, &output_path).inspect_err(|e| {
        crate::diagnostics::warn(format!("remove background {input_path}: {e:#}"));
    })
}

/// Adjustments that balance the picture of [path] between [from_ms] and
/// [to_ms], measured on a few frames: brightness towards a mid exposure,
/// contrast towards a healthy spread, saturation towards lively colour.
pub fn suggest_adjustments(path: String, from_ms: i64, to_ms: i64) -> Result<SuggestedAdjustments> {
    crate::render::analysis::suggest(&path, from_ms, to_ms)
}
