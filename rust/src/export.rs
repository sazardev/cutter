//! Rendering a timeline to an MP4 file: H.264 video and AAC sound.

use anyhow::{bail, Context, Result};
use ff::util::error::EAGAIN;
use ffmpeg_next as ff;

use crate::api::types::{ExportSettings, Timeline};
use crate::media::audio::{CHANNELS, SAMPLE_RATE};
use crate::media::init;
use crate::render::compositor::Compositor;
use crate::render::mixer::Mixer;

/// H.264 encoders in order of preference: the hardware one on Android, then
/// x264, then OpenH264.
const H264_ENCODERS: [&str; 3] = ["h264_mediacodec", "libx264", "libopenh264"];

/// Why an export stopped early.
#[derive(Debug)]
pub struct Cancelled {}

impl std::fmt::Display for Cancelled {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("export cancelled")
    }
}

impl std::error::Error for Cancelled {}

struct Output {
    octx: ff::format::context::Output,
    video: ff::encoder::Video,
    /// The pixel format the H.264 encoder takes; the scaler must produce it.
    video_format: ff::format::Pixel,
    video_index: usize,
    video_tb: ff::Rational,
    audio: ff::encoder::Audio,
    audio_index: usize,
    audio_tb: ff::Rational,
}

impl Output {
    fn drain_video(&mut self) -> Result<()> {
        let mut packet = ff::Packet::empty();
        loop {
            match self.video.receive_packet(&mut packet) {
                Ok(()) => {
                    packet.set_stream(self.video_index);
                    packet.rescale_ts(
                        self.video_tb,
                        self.octx.stream(self.video_index).unwrap().time_base(),
                    );
                    packet.write_interleaved(&mut self.octx)?;
                }
                Err(ff::Error::Other { errno }) if errno == EAGAIN => return Ok(()),
                Err(ff::Error::Eof) => return Ok(()),
                Err(e) => return Err(e.into()),
            }
        }
    }

    fn drain_audio(&mut self) -> Result<()> {
        let mut packet = ff::Packet::empty();
        loop {
            match self.audio.receive_packet(&mut packet) {
                Ok(()) => {
                    packet.set_stream(self.audio_index);
                    packet.rescale_ts(
                        self.audio_tb,
                        self.octx.stream(self.audio_index).unwrap().time_base(),
                    );
                    packet.write_interleaved(&mut self.octx)?;
                }
                Err(ff::Error::Other { errno }) if errno == EAGAIN => return Ok(()),
                Err(ff::Error::Eof) => return Ok(()),
                Err(e) => return Err(e.into()),
            }
        }
    }

    /// Sends a picture to the encoder.
    ///
    /// A hardware encoder answers `EAGAIN` while its input queue is full: the
    /// packets made so far have to be taken before it accepts more, so drain
    /// them and try again. Without this an export on Android fails with
    /// "Try again" as soon as the encoder falls behind.
    fn send_video(&mut self, frame: &ff::frame::Video) -> Result<()> {
        let mut tries = 0;
        loop {
            match self.video.send_frame(frame) {
                Ok(()) => return Ok(()),
                Err(ff::Error::Other { errno }) if errno == EAGAIN => {
                    self.drain_video()?;
                    tries += 1;
                    if tries > 5000 {
                        bail!("the H.264 encoder stopped taking frames");
                    }
                    std::thread::sleep(std::time::Duration::from_millis(1));
                }
                Err(e) => return Err(e.into()),
            }
        }
    }

    /// Sends sound to the encoder, draining packets while it is full.
    fn send_audio(&mut self, frame: &ff::frame::Audio) -> Result<()> {
        let mut tries = 0;
        loop {
            match self.audio.send_frame(frame) {
                Ok(()) => return Ok(()),
                Err(ff::Error::Other { errno }) if errno == EAGAIN => {
                    self.drain_audio()?;
                    tries += 1;
                    if tries > 5000 {
                        bail!("the AAC encoder stopped taking frames");
                    }
                    std::thread::sleep(std::time::Duration::from_millis(1));
                }
                Err(e) => return Err(e.into()),
            }
        }
    }

    fn finish_video(&mut self) -> Result<()> {
        let mut tries = 0;
        loop {
            match self.video.send_eof() {
                Ok(()) => return Ok(()),
                Err(ff::Error::Other { errno }) if errno == EAGAIN => {
                    self.drain_video()?;
                    tries += 1;
                    if tries > 5000 {
                        bail!("the H.264 encoder would not finish");
                    }
                    std::thread::sleep(std::time::Duration::from_millis(1));
                }
                Err(e) => return Err(e.into()),
            }
        }
    }

    fn finish_audio(&mut self) -> Result<()> {
        let mut tries = 0;
        loop {
            match self.audio.send_eof() {
                Ok(()) => return Ok(()),
                Err(ff::Error::Other { errno }) if errno == EAGAIN => {
                    self.drain_audio()?;
                    tries += 1;
                    if tries > 5000 {
                        bail!("the AAC encoder would not finish");
                    }
                    std::thread::sleep(std::time::Duration::from_millis(1));
                }
                Err(e) => return Err(e.into()),
            }
        }
    }
}

/// The H.264 codec an export uses, with the pixel format it accepts.
struct VideoCodec {
    codec: ff::Codec,
    format: ff::format::Pixel,
}

/// The first encoder and pixel format that open at [s]'s size.
///
/// `h264_mediacodec` is tried with NV12 first: some devices (and the emulator)
/// accept a planar YUV420P configuration and then never hand out an input
/// buffer, which fails the export with EAGAIN. NV12 is the layout those
/// encoders are made for; planar stays as the fallback.
fn choose_video_codec(s: &ExportSettings) -> Result<VideoCodec> {
    for name in H264_ENCODERS {
        let Some(codec) = ff::encoder::find_by_name(name) else {
            continue;
        };
        let formats: &[ff::format::Pixel] = if name == "h264_mediacodec" {
            &[ff::format::Pixel::NV12, ff::format::Pixel::YUV420P]
        } else {
            &[ff::format::Pixel::YUV420P]
        };
        for &format in formats {
            let opened = ff::codec::context::Context::new_with_codec(codec)
                .encoder()
                .video()
                .map(|mut ctx| {
                    ctx.set_width(s.width);
                    ctx.set_height(s.height);
                    ctx.set_format(format);
                    ctx.set_time_base(ff::Rational(1, s.fps as i32));
                    ctx.open().is_ok()
                })
                .unwrap_or(false);
            if opened {
                return Ok(VideoCodec { codec, format });
            }
        }
    }
    Ok(VideoCodec {
        codec: ff::encoder::find(ff::codec::Id::MPEG4).context("no H.264 encoder available")?,
        format: ff::format::Pixel::YUV420P,
    })
}

fn open_output(path: &str, s: &ExportSettings) -> Result<Output> {
    let mut octx =
        ff::format::output_as(&path, "mp4").with_context(|| format!("cannot create {path}"))?;
    let global_header = octx
        .format()
        .flags()
        .contains(ff::format::Flags::GLOBAL_HEADER);

    let VideoCodec { codec, format } = choose_video_codec(s)?;
    let video_index = octx.add_stream(codec)?.index();
    let mut enc = ff::codec::context::Context::new_with_codec(codec)
        .encoder()
        .video()?;
    enc.set_width(s.width);
    enc.set_height(s.height);
    enc.set_format(format);
    let video_tb = ff::Rational(1, s.fps as i32);
    enc.set_time_base(video_tb);
    enc.set_frame_rate(Some(ff::Rational(s.fps as i32, 1)));
    enc.set_bit_rate(s.video_bitrate as usize);
    enc.set_gop(s.fps * 2);
    // MediaCodec must not get the global-header flag: FFmpeg then builds the
    // extradata at open by sending a dummy frame, signalling end of stream and
    // flushing the codec, and after that flush the Android encoder (the
    // emulator's C2 one, at least) never hands out an input buffer again. The
    // MP4 muxer takes the SPS/PPS from the first packet instead.
    if global_header && codec.name() != "h264_mediacodec" {
        enc.set_flags(ff::codec::Flags::GLOBAL_HEADER);
    }
    let mut opts = ff::Dictionary::new();
    if codec.name() == "libx264" {
        opts.set("preset", &s.encoder_preset);
        opts.set("profile", "high");
    }
    let video = enc.open_with(opts)?;
    octx.stream_mut(video_index).unwrap().set_parameters(&video);
    octx.stream_mut(video_index)
        .unwrap()
        .set_time_base(video_tb);

    let aac = ff::encoder::find(ff::codec::Id::AAC).context("no AAC encoder available")?;
    let audio_index = octx.add_stream(aac)?.index();
    let mut aenc = ff::codec::context::Context::new_with_codec(aac)
        .encoder()
        .audio()?;
    aenc.set_rate(SAMPLE_RATE as i32);
    aenc.set_channel_layout(ff::ChannelLayout::STEREO);
    aenc.set_format(ff::format::Sample::F32(ff::format::sample::Type::Planar));
    aenc.set_bit_rate(s.audio_bitrate as usize);
    let audio_tb = ff::Rational(1, SAMPLE_RATE as i32);
    aenc.set_time_base(audio_tb);
    if global_header {
        aenc.set_flags(ff::codec::Flags::GLOBAL_HEADER);
    }
    let audio = aenc.open_as(aac)?;
    octx.stream_mut(audio_index).unwrap().set_parameters(&audio);
    octx.stream_mut(audio_index)
        .unwrap()
        .set_time_base(audio_tb);

    octx.write_header()?;
    Ok(Output {
        octx,
        video,
        video_format: format,
        video_index,
        video_tb,
        audio,
        audio_index,
        audio_tb,
    })
}

/// Renders [timeline] into [path]. [progress] receives the fraction done
/// after every frame and returns false to cancel.
pub fn export(
    timeline: &Timeline,
    settings: &ExportSettings,
    path: &str,
    mut progress: impl FnMut(f64) -> bool,
) -> Result<()> {
    init();
    let duration = timeline.duration_ms();
    if duration <= 0 {
        bail!("the timeline is empty");
    }
    let s = ExportSettings {
        width: settings.width.max(2) & !1,
        height: settings.height.max(2) & !1,
        fps: settings.fps.clamp(1, 120),
        video_bitrate: settings.video_bitrate.max(500_000),
        audio_bitrate: settings.audio_bitrate.clamp(64_000, 320_000),
        encoder_preset: match settings.encoder_preset.as_str() {
            p @ ("ultrafast" | "veryfast" | "faster" | "fast" | "medium" | "slow") => p.to_owned(),
            _ => "fast".to_owned(),
        },
    };
    let begun = std::time::Instant::now();
    crate::diagnostics::info(format!(
        "export start {path}: {}x{} @{} fps, {} ms",
        s.width, s.height, s.fps, duration
    ));
    let mut out = open_output(path, &s)?;
    // Export may use most of the machine, but leaves cores for the encoder.
    let cores = std::thread::available_parallelism().map_or(2, |n| n.get());
    let mut compositor = Compositor::for_export((cores / 2).clamp(1, 4));
    let mut mixer = Mixer::default();
    let mut scaler = ff::software::scaling::Context::get(
        ff::format::Pixel::RGBA,
        s.width,
        s.height,
        out.video_format,
        s.width,
        s.height,
        ff::software::scaling::Flags::BICUBIC,
    )?;
    let frame_size = (out.audio.frame_size() as usize).max(1024);
    let total_frames = (duration * i64::from(s.fps) + 999) / 1000;
    let total_samples = duration * i64::from(SAMPLE_RATE) / 1000;
    let mut rgba = Vec::new();
    let mut mix = vec![0f32; frame_size * CHANNELS];
    let mut samples_done = 0i64;

    for i in 0..total_frames {
        let t = i * 1000 / i64::from(s.fps);
        compositor.render(timeline, t, s.width, s.height, &mut rgba);
        let mut src = ff::frame::Video::new(ff::format::Pixel::RGBA, s.width, s.height);
        let stride = src.stride(0);
        let row = s.width as usize * 4;
        for y in 0..s.height as usize {
            src.data_mut(0)[y * stride..y * stride + row]
                .copy_from_slice(&rgba[y * row..(y + 1) * row]);
        }
        let mut yuv = ff::frame::Video::empty();
        scaler.run(&src, &mut yuv)?;
        yuv.set_pts(Some(i));
        out.send_video(&yuv)?;
        out.drain_video()?;

        // Keep the sound up to the end of this picture.
        let audio_until = ((i + 1) * i64::from(SAMPLE_RATE) / i64::from(s.fps)).min(total_samples);
        while samples_done < audio_until {
            mixer.mix(timeline, samples_done, &mut mix);
            let mut frame = ff::frame::Audio::new(
                ff::format::Sample::F32(ff::format::sample::Type::Planar),
                frame_size,
                ff::ChannelLayout::STEREO,
            );
            frame.set_rate(SAMPLE_RATE);
            for c in 0..CHANNELS {
                let plane: &mut [f32] = frame.plane_mut(c);
                for (k, v) in plane.iter_mut().enumerate().take(frame_size) {
                    *v = mix[k * CHANNELS + c];
                }
            }
            frame.set_pts(Some(samples_done));
            out.send_audio(&frame)?;
            out.drain_audio()?;
            samples_done += frame_size as i64;
        }

        if !progress((i + 1) as f64 / total_frames as f64) {
            drop(out);
            let _ = std::fs::remove_file(path);
            return Err(Cancelled {}.into());
        }
    }

    out.finish_video()?;
    out.drain_video()?;
    out.finish_audio()?;
    out.drain_audio()?;
    out.octx.write_trailer()?;
    let took = begun.elapsed().as_secs_f64();
    crate::diagnostics::info(format!(
        "export done in {took:.1} s ({:.2}x real time)",
        duration as f64 / 1000.0 / took.max(0.001)
    ));
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::export;
    use crate::api::types::{EngineMediaKind, ExportSettings};
    use crate::media::probe::probe;
    use crate::test_support::{clip, fixtures, layer, vertical};

    #[test]
    fn renders_a_playable_mp4_with_sound() {
        let f = fixtures();
        let timeline = vertical(vec![
            layer(
                EngineMediaKind::Image,
                vec![clip(&f.image, EngineMediaKind::Image, 0, 0, 500)],
            ),
            layer(
                EngineMediaKind::Video,
                vec![clip(&f.video, EngineMediaKind::Video, 0, 500, 1500)],
            ),
            layer(
                EngineMediaKind::Audio,
                vec![clip(&f.tone, EngineMediaKind::Audio, 0, 0, 1000)],
            ),
        ]);
        let path = std::env::temp_dir().join(format!("cutter-export-{}.mp4", std::process::id()));
        let path = path.to_str().unwrap();
        let mut last = 0.0;
        export(
            &timeline,
            &ExportSettings {
                width: 360,
                height: 640,
                fps: 30,
                video_bitrate: 2_000_000,
                audio_bitrate: 128_000,
                encoder_preset: "veryfast".into(),
            },
            path,
            |p| {
                assert!(p >= last);
                last = p;
                true
            },
        )
        .unwrap();
        assert!((last - 1.0).abs() < 1e-9);
        let info = probe(path).unwrap();
        assert_eq!(
            (info.kind, info.width, info.height),
            (EngineMediaKind::Video, 360, 640)
        );
        assert!(info.has_audio);
        assert!(
            (info.duration_ms - 1000).abs() < 100,
            "{}",
            info.duration_ms
        );
    }

    #[test]
    fn cancelling_removes_the_partial_file() {
        let f = fixtures();
        let timeline = vertical(vec![layer(
            EngineMediaKind::Video,
            vec![clip(&f.video, EngineMediaKind::Video, 0, 0, 3000)],
        )]);
        let path = std::env::temp_dir().join(format!("cutter-cancel-{}.mp4", std::process::id()));
        let path = path.to_str().unwrap();
        let err = export(
            &timeline,
            &ExportSettings {
                width: 360,
                height: 640,
                fps: 30,
                video_bitrate: 1_000_000,
                audio_bitrate: 128_000,
                encoder_preset: "veryfast".into(),
            },
            path,
            |p| p < 0.2,
        )
        .unwrap_err();
        assert!(err.is::<super::Cancelled>());
        assert!(!std::path::Path::new(path).exists());
    }
}

#[cfg(test)]
mod bench {
    use std::time::Instant;

    use crate::api::types::ExportSettings;

    #[test]
    #[ignore]
    fn bench_export_many_layers() {
        let Some(tl) = crate::render::compositor::bench_timeline(1080, 1920) else {
            return;
        };
        let path = std::env::temp_dir().join("cutter-bench-export.mp4");
        let started = Instant::now();
        super::export(
            &tl,
            &ExportSettings {
                width: 1080,
                height: 1920,
                fps: 30,
                video_bitrate: 12_000_000,
                audio_bitrate: 192_000,
                encoder_preset: "fast".into(),
            },
            path.to_str().unwrap(),
            |_| true,
        )
        .unwrap();
        let secs = started.elapsed().as_secs_f64();
        let media = tl.duration_ms() as f64 / 1000.0;
        eprintln!(
            "BENCH export 1080x1920 {media:.1}s of media in {secs:.1}s = {:.2}x real time",
            media / secs
        );
    }
}
