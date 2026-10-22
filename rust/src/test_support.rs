//! Media fixtures for the tests, made once per run with the ffmpeg CLI.

use std::path::PathBuf;
use std::process::Command;
use std::sync::OnceLock;

use crate::api::types::{EngineMediaKind, Timeline, TimelineClip, TimelineLayer};

pub struct Fixtures {
    /// 640x360, 30 fps, 3 s, with a 440 Hz tone.
    pub video: String,
    /// 640x360 stored, displayed rotated 90 degrees: 360x640.
    pub rotated: String,
    /// 320x240 PNG.
    pub image: String,
    /// 2 s, 440 Hz, AAC.
    pub tone: String,
}

fn ffmpeg(args: &[&str]) {
    let status = Command::new("ffmpeg")
        .args(["-hide_banner", "-loglevel", "error", "-y"])
        .args(args)
        .status()
        .expect("the tests need the ffmpeg CLI");
    assert!(status.success(), "ffmpeg {args:?} failed");
}

pub fn fixtures() -> &'static Fixtures {
    static FIXTURES: OnceLock<Fixtures> = OnceLock::new();
    FIXTURES.get_or_init(|| {
        let dir: PathBuf =
            std::env::temp_dir().join(format!("cutter-engine-fixtures-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = |name: &str| dir.join(name).to_string_lossy().into_owned();
        let (video, rotated, image, tone) = (
            path("video.mp4"),
            path("rotated.mp4"),
            path("image.png"),
            path("tone.m4a"),
        );
        ffmpeg(&[
            "-f",
            "lavfi",
            "-i",
            "testsrc2=size=640x360:rate=30:duration=3",
            "-f",
            "lavfi",
            "-i",
            "sine=frequency=440:duration=3",
            "-c:v",
            "libx264",
            "-g",
            "30",
            "-pix_fmt",
            "yuv420p",
            "-c:a",
            "aac",
            "-shortest",
            &video,
        ]);
        ffmpeg(&[
            "-display_rotation:v:0",
            "90",
            "-i",
            &video,
            "-c",
            "copy",
            &rotated,
        ]);
        ffmpeg(&[
            "-f",
            "lavfi",
            "-i",
            "testsrc2=size=320x240",
            "-frames:v",
            "1",
            &image,
        ]);
        ffmpeg(&[
            "-f",
            "lavfi",
            "-i",
            "sine=frequency=440:duration=2",
            "-c:a",
            "aac",
            &tone,
        ]);
        Fixtures {
            video,
            rotated,
            image,
            tone,
        }
    })
}

pub fn clip(
    path: &str,
    kind: EngineMediaKind,
    start_ms: i64,
    in_ms: i64,
    out_ms: i64,
) -> TimelineClip {
    TimelineClip {
        path: path.to_owned(),
        kind,
        start_ms,
        in_ms,
        out_ms,
        reversed: false,
        volume: 1.0,
        filter: None,
        brightness: 0.0,
        contrast: 0.0,
        saturation: 0.0,
        x: 0.0,
        y: 0.0,
        scale: 1.0,
        rotation: 0.0,
        opacity: 1.0,
        flip_x: false,
        fill: false,
        crop_left: 0.0,
        crop_top: 0.0,
        crop_right: 0.0,
        crop_bottom: 0.0,
        speed: 1.0,
        fade_in_ms: 0,
        fade_out_ms: 0,
        blur: 0.0,
        vignette: 0.0,
        grain: 0.0,
        pixelate: 0.0,
        sharpen: 0.0,
        anim_in: None,
        anim_in_ms: 0,
        anim_out: None,
        anim_out_ms: 0,
        text: None,
    }
}

pub fn layer(kind: EngineMediaKind, clips: Vec<TimelineClip>) -> TimelineLayer {
    TimelineLayer {
        kind,
        volume: 1.0,
        muted: false,
        clips,
    }
}

pub fn vertical(layers: Vec<TimelineLayer>) -> Timeline {
    Timeline {
        width: 360,
        height: 640,
        fps: 30,
        layers,
    }
}
