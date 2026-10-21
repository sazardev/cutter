use anyhow::{bail, Context, Result};
use ffmpeg_next as ff;

use super::{init, stream_rotation};
use crate::api::types::{EngineMediaKind, MediaInfo};

/// Image formats are demuxed as a single frame by these FFmpeg demuxers.
fn is_image_demuxer(name: &str) -> bool {
    name.contains("image2") || name.ends_with("_pipe") || name == "webp" || name == "gif"
}

/// The first video stream that is not cover art embedded in an audio file.
pub fn real_video_stream(
    input: &ff::format::context::Input,
) -> Option<ff::format::stream::Stream<'_>> {
    input.streams().find(|s| {
        s.parameters().medium() == ff::media::Type::Video
            && !s
                .disposition()
                .contains(ff::format::stream::Disposition::ATTACHED_PIC)
    })
}

/// Opens [path] and describes what it holds. Fails on files FFmpeg cannot
/// read or that hold neither pictures nor sound.
pub fn probe(path: &str) -> Result<MediaInfo> {
    init();
    let input = ff::format::input(&path).with_context(|| format!("cannot open {path}"))?;
    let demuxer = input.format().name().to_owned();
    let has_audio = input.streams().best(ff::media::Type::Audio).is_some();
    let container_ms = if input.duration() > 0 {
        input.duration() * 1000 / i64::from(ff::ffi::AV_TIME_BASE)
    } else {
        0
    };

    if let Some(stream) = real_video_stream(&input) {
        let decoder = ff::codec::Context::from_parameters(stream.parameters())?
            .decoder()
            .video()
            .context("unsupported video codec")?;
        let rotation = stream_rotation(&stream);
        let (w, h) = if rotation % 180 == 0 {
            (decoder.width(), decoder.height())
        } else {
            (decoder.height(), decoder.width())
        };
        let rate = stream.avg_frame_rate();
        let frame_rate = if rate.denominator() > 0 {
            f64::from(rate)
        } else {
            0.0
        };
        let still = is_image_demuxer(&demuxer) || (container_ms == 0 && stream.frames() <= 1);
        if still {
            return Ok(MediaInfo {
                kind: EngineMediaKind::Image,
                duration_ms: 0,
                width: w,
                height: h,
                has_audio: false,
                frame_rate: 0.0,
                rotation,
            });
        }
        let stream_ms = super::ts_to_ms(stream.duration(), stream.time_base());
        return Ok(MediaInfo {
            kind: EngineMediaKind::Video,
            duration_ms: if container_ms > 0 {
                container_ms
            } else {
                stream_ms
            },
            width: w,
            height: h,
            has_audio,
            frame_rate,
            rotation,
        });
    }

    if has_audio {
        return Ok(MediaInfo {
            kind: EngineMediaKind::Audio,
            duration_ms: container_ms,
            width: 0,
            height: 0,
            has_audio: true,
            frame_rate: 0.0,
            rotation: 0,
        });
    }
    bail!("{path} holds neither video, image nor audio")
}

#[cfg(test)]
mod tests {
    use super::probe;
    use crate::api::types::EngineMediaKind;
    use crate::test_support::fixtures;

    #[test]
    fn describes_a_video_with_sound() {
        let info = probe(&fixtures().video).unwrap();
        assert_eq!(info.kind, EngineMediaKind::Video);
        assert_eq!((info.width, info.height), (640, 360));
        assert!(info.has_audio);
        assert!(
            (info.duration_ms - 3000).abs() < 100,
            "{}",
            info.duration_ms
        );
    }

    #[test]
    fn swaps_the_size_of_a_rotated_video() {
        let info = probe(&fixtures().rotated).unwrap();
        assert_eq!((info.width, info.height), (360, 640));
        assert!(
            info.rotation == 90 || info.rotation == 270,
            "{}",
            info.rotation
        );
    }

    #[test]
    fn describes_an_image_and_a_sound() {
        let image = probe(&fixtures().image).unwrap();
        assert_eq!(
            (image.kind, image.width, image.height, image.duration_ms),
            (EngineMediaKind::Image, 320, 240, 0)
        );
        let tone = probe(&fixtures().tone).unwrap();
        assert_eq!(tone.kind, EngineMediaKind::Audio);
        assert!((tone.duration_ms - 2000).abs() < 100);
    }

    #[test]
    fn rejects_a_file_that_is_not_media() {
        let path = std::env::temp_dir().join("cutter-not-media.txt");
        std::fs::write(&path, "hello").unwrap();
        assert!(probe(path.to_str().unwrap()).is_err());
    }
}
