//! Plain data that crosses the FFI boundary. Flutter Rust Bridge mirrors each
//! type as an immutable Dart class.

/// What a media file holds, as the engine sees it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EngineMediaKind {
    Video,
    Image,
    Audio,
    /// Words drawn by the engine; the clip has no file.
    Text,
}

/// What the engine learned about a file when it probed it.
#[derive(Debug, Clone)]
pub struct MediaInfo {
    pub kind: EngineMediaKind,
    /// Duration in milliseconds; 0 for still images.
    pub duration_ms: i64,
    /// Display width in pixels, after rotation; 0 for audio.
    pub width: u32,
    /// Display height in pixels, after rotation; 0 for audio.
    pub height: u32,
    pub has_audio: bool,
    pub frame_rate: f64,
    /// Clockwise rotation the player must apply, in degrees (0, 90, 180, 270).
    pub rotation: i32,
}

/// The project as the engine renders it: an immutable snapshot sent on every
/// change. Layer 0 is the front-most.
#[derive(Debug, Clone, Default)]
pub struct Timeline {
    pub width: u32,
    pub height: u32,
    pub fps: u32,
    pub layers: Vec<TimelineLayer>,
}

#[derive(Debug, Clone)]
pub struct TimelineLayer {
    pub kind: EngineMediaKind,
    pub volume: f32,
    pub muted: bool,
    pub clips: Vec<TimelineClip>,
}

#[derive(Debug, Clone)]
pub struct TimelineClip {
    pub path: String,
    pub kind: EngineMediaKind,
    pub start_ms: i64,
    pub in_ms: i64,
    pub out_ms: i64,
    pub reversed: bool,
    pub volume: f32,
    /// One of `mono`, `warm`, `cool`, `vintage`, or None.
    pub filter: Option<String>,
    /// Each in -1.0..=1.0, 0 meaning unchanged.
    pub brightness: f32,
    pub contrast: f32,
    pub saturation: f32,
    /// Centre offset as a fraction of the canvas width / height from its
    /// centre; positive is right / down.
    pub x: f32,
    pub y: f32,
    /// Scale on top of the fit (or fill) size.
    pub scale: f32,
    /// Clockwise degrees.
    pub rotation: f32,
    pub opacity: f32,
    pub flip_x: bool,
    /// Cover the canvas instead of fitting inside it.
    pub fill: bool,
    /// Fractions of the source cut from each edge.
    pub crop_left: f32,
    pub crop_top: f32,
    pub crop_right: f32,
    pub crop_bottom: f32,
    /// Playback speed; the clip lasts its source span divided by it.
    pub speed: f32,
    /// Sound fades, in timeline milliseconds.
    pub fade_in_ms: i64,
    pub fade_out_ms: i64,
    /// Spatial effects, each in 0.0..=1.0 with 0 meaning off.
    pub blur: f32,
    pub vignette: f32,
    pub grain: f32,
    pub pixelate: f32,
    pub sharpen: f32,
    /// How the clip comes in and goes out: one of `render::animation`'s ids
    /// or None, and how long each lasts in timeline milliseconds.
    pub anim_in: Option<String>,
    pub anim_in_ms: i64,
    pub anim_out: Option<String>,
    pub anim_out_ms: i64,
    /// What a text clip says and how it looks; None for any other clip.
    pub text: Option<TextSpec>,
}

/// How the lines of a text sit against each other.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TextAlign {
    Left,
    Center,
    Right,
}

/// How a text comes in and goes out, over the first and last moments of its
/// clip.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TextAnimation {
    None,
    Fade,
    Pop,
    SlideUp,
}

/// The words of a text clip and their look. Colours are `0xAARRGGBB`.
#[derive(Debug, Clone, PartialEq)]
pub struct TextSpec {
    /// The words; `\n` starts a new line.
    pub content: String,
    /// One of `sans`, `serif`, `mono`, `anton`, `bebas`, `bangers`, `lobster`,
    /// `pacifico`, `marker`; anything else draws as `sans`.
    pub font: String,
    /// Font size as a fraction of the canvas height.
    pub size: f32,
    pub color: u32,
    pub bold: bool,
    pub italic: bool,
    pub align: TextAlign,
    pub stroke_color: u32,
    /// Outline thickness as a fraction of the font size; 0 is none.
    pub stroke_width: f32,
    /// Shadow strength, 0.0 (none) to 1.0.
    pub shadow: f32,
    /// Fill behind the words; an alpha of 0 is none.
    pub background: u32,
    /// Extra space between letters, as a fraction of the font size.
    pub letter_spacing: f32,
    pub animation: TextAnimation,
}

/// The size of the picture a text draws.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TextSize {
    pub width: u32,
    pub height: u32,
}

impl TimelineClip {
    pub fn rate(&self) -> f64 {
        f64::from(self.speed).clamp(0.05, 16.0)
    }

    pub fn duration_ms(&self) -> i64 {
        ((self.out_ms - self.in_ms) as f64 / self.rate()).round() as i64
    }

    pub fn end_ms(&self) -> i64 {
        self.start_ms + self.duration_ms()
    }

    pub fn is_active_at(&self, t_ms: i64) -> bool {
        t_ms >= self.start_ms && t_ms < self.end_ms()
    }

    /// The source time played at timeline time [t_ms].
    pub fn source_ms_at(&self, t_ms: i64) -> i64 {
        let offset = ((t_ms - self.start_ms) as f64 * self.rate()).round() as i64;
        if self.reversed {
            (self.out_ms - offset - 1).max(self.in_ms)
        } else {
            self.in_ms + offset
        }
    }
}

impl Timeline {
    pub fn duration_ms(&self) -> i64 {
        self.layers
            .iter()
            .flat_map(|l| l.clips.iter())
            .map(TimelineClip::end_ms)
            .max()
            .unwrap_or(0)
    }
}

/// A small RGBA picture of a source at one point in time.
#[derive(Debug, Clone)]
pub struct Thumbnail {
    pub time_ms: i64,
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
}

/// Where the preview is, sent to Flutter while it plays or seeks.
#[derive(Debug, Clone)]
pub struct PlaybackState {
    pub position_ms: i64,
    pub playing: bool,
}

/// Settings of a finished render.
#[derive(Debug, Clone)]
pub struct ExportSettings {
    pub width: u32,
    pub height: u32,
    pub fps: u32,
    pub video_bitrate: u32,
    pub audio_bitrate: u32,
    /// Encoder effort: `veryfast` for drafts, `fast`, or `medium` for the
    /// best compression at a given bitrate.
    pub encoder_preset: String,
}

/// Adjustments that bring a picture to a balanced exposure, contrast and
/// colour, each in -1..=1.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SuggestedAdjustments {
    pub brightness: f32,
    pub contrast: f32,
    pub saturation: f32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExportStage {
    Running,
    Done,
    Failed,
    Cancelled,
}

/// One step of an export; the last one has a stage other than `Running`.
#[derive(Debug, Clone)]
pub struct ExportEvent {
    pub stage: ExportStage,
    /// Fraction done, 0.0 to 1.0.
    pub progress: f64,
    /// Why the export failed, when it did.
    pub message: Option<String>,
}

impl ExportEvent {
    pub fn running(progress: f64) -> Self {
        Self {
            stage: ExportStage::Running,
            progress,
            message: None,
        }
    }

    pub fn finished(stage: ExportStage, message: Option<String>) -> Self {
        Self {
            stage,
            progress: 1.0,
            message,
        }
    }
}

/// What the engine has been doing, for the diagnostics panel and logs.
#[derive(Debug, Clone)]
pub struct EngineDiagnostics {
    pub frames_rendered: u64,
    /// Mean and worst composition time of the recent preview frames.
    pub avg_render_ms: f64,
    pub max_render_ms: f64,
    /// Preview frames that took longer than one frame of the canvas.
    pub late_frames: u64,
    pub open_video_decoders: u32,
    pub open_audio_decoders: u32,
    /// Bytes held by decoded-frame caches.
    pub cache_bytes: u64,
    /// Preview resolution relative to full size, lowered while playing when
    /// frames get expensive.
    pub preview_scale: f64,
    /// The latest engine log lines, oldest first.
    pub log: Vec<String>,
}
