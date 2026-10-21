use std::collections::VecDeque;

use anyhow::{Context, Result};
use ff::util::error::EAGAIN;
use ffmpeg_next as ff;

use super::{init, ts_to_ms};

/// Every source is resampled to this rate and to interleaved stereo f32.
pub const SAMPLE_RATE: u32 = 48_000;
pub const CHANNELS: usize = 2;
pub const FRAMES_PER_MS: i64 = SAMPLE_RATE as i64 / 1000;

const SEEK_LEAD_MS: i64 = 200;

/// A request further ahead than this from what is buffered seeks instead of
/// decoding through.
const MAX_GAP_FRAMES: i64 = SAMPLE_RATE as i64 / 4;

/// The sound of one file as a stream of 48 kHz stereo samples, addressable by
/// source time.
pub struct AudioReader {
    input: ff::format::context::Input,
    stream_index: usize,
    time_base: ff::Rational,
    start_ts: i64,
    decoder: ff::decoder::Audio,
    resampler: Option<(
        (ff::format::Sample, u64, u32),
        ff::software::resampling::Context,
    )>,
    eof_sent: bool,
    finished: bool,
    /// Interleaved samples; [buf_frame] is the source frame index of buf[0].
    buf: VecDeque<f32>,
    buf_frame: i64,
}

// SAFETY: the FFmpeg contexts are owned exclusively by the reader and only
// used from the thread that owns it at a time.
unsafe impl Send for AudioReader {}

impl AudioReader {
    pub fn open(path: &str) -> Result<Self> {
        init();
        let input = ff::format::input(&path).with_context(|| format!("cannot open {path}"))?;
        let stream = input
            .streams()
            .best(ff::media::Type::Audio)
            .context("no audio stream")?;
        let stream_index = stream.index();
        let time_base = stream.time_base();
        let start_ts = if stream.start_time() == ff::ffi::AV_NOPTS_VALUE {
            0
        } else {
            stream.start_time()
        };
        let decoder = ff::codec::Context::from_parameters(stream.parameters())?
            .decoder()
            .audio()
            .context("unsupported audio codec")?;
        crate::diagnostics::audio_decoder_opened(1);
        Ok(Self {
            input,
            stream_index,
            time_base,
            start_ts,
            decoder,
            resampler: None,
            eof_sent: false,
            finished: false,
            buf: VecDeque::new(),
            buf_frame: -1,
        })
    }

    /// Fills [out] (interleaved stereo) with the sound starting at sample
    /// frame [want] of the source (48 kHz). Silence past the end of the file.
    pub fn fill(&mut self, want: i64, out: &mut [f32]) -> Result<()> {
        let buffered_end = self.buf_frame + (self.buf.len() / CHANNELS) as i64;
        if self.buf_frame < 0 || want < self.buf_frame || want > buffered_end + MAX_GAP_FRAMES {
            // Land a little early: decoding then walks up to the exact sample
            // instead of starting late and padding with silence.
            self.seek(want / FRAMES_PER_MS - SEEK_LEAD_MS)?;
        }
        let frames = out.len() / CHANNELS;
        while !self.finished
            && self.buf_frame + ((self.buf.len() / CHANNELS) as i64) < want + frames as i64
        {
            self.decode_more()?;
        }
        // Drop what lies before the request.
        if self.buf_frame >= 0 && want > self.buf_frame {
            let drop = ((want - self.buf_frame) as usize * CHANNELS).min(self.buf.len());
            self.buf.drain(..drop);
            self.buf_frame += (drop / CHANNELS) as i64;
        }
        let lead = if self.buf_frame > want {
            ((self.buf_frame - want) as usize * CHANNELS).min(out.len())
        } else {
            0
        };
        out[..lead].fill(0.0);
        let mut i = lead;
        for s in self.buf.iter().take(out.len() - lead) {
            out[i] = *s;
            i += 1;
        }
        out[i..].fill(0.0);
        Ok(())
    }

    fn seek(&mut self, ms: i64) -> Result<()> {
        let start_us = ts_to_ms(self.start_ts, self.time_base) * 1000;
        let target = (ms * 1000 + start_us).max(0);
        let _ = self.input.seek(target, ..target + 1);
        self.decoder.flush();
        self.resampler = None;
        self.eof_sent = false;
        self.finished = false;
        self.buf.clear();
        self.buf_frame = -1;
        Ok(())
    }

    fn decode_more(&mut self) -> Result<()> {
        loop {
            let mut frame = ff::frame::Audio::empty();
            match self.decoder.receive_frame(&mut frame) {
                Ok(()) => {
                    self.push(&frame)?;
                    return Ok(());
                }
                Err(ff::Error::Eof) => {
                    self.finished = true;
                    return Ok(());
                }
                Err(ff::Error::Other { errno }) if errno == EAGAIN => {}
                Err(e) => return Err(e.into()),
            }
            if self.eof_sent {
                self.finished = true;
                return Ok(());
            }
            let mut packet = ff::Packet::empty();
            match packet.read(&mut self.input) {
                Ok(()) => {
                    if packet.stream() == self.stream_index {
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

    fn push(&mut self, frame: &ff::frame::Audio) -> Result<()> {
        let mut layout = frame.channel_layout();
        if layout.is_empty() || layout.channels() == 0 {
            layout = ff::ChannelLayout::default(i32::from(frame.channels().max(1)));
        }
        let key = (frame.format(), layout.bits(), frame.rate());
        if self.resampler.as_ref().map(|(k, _)| *k) != Some(key) {
            let ctx = ff::software::resampling::Context::get(
                frame.format(),
                layout,
                frame.rate(),
                ff::format::Sample::F32(ff::format::sample::Type::Packed),
                ff::ChannelLayout::STEREO,
                SAMPLE_RATE,
            )?;
            self.resampler = Some((key, ctx));
        }
        let mut frame = frame.clone();
        frame.set_channel_layout(layout);
        let mut out = ff::frame::Audio::empty();
        self.resampler.as_mut().unwrap().1.run(&frame, &mut out)?;
        if self.buf_frame < 0 {
            let ts = frame.timestamp().or(frame.pts()).unwrap_or(self.start_ts);
            self.buf_frame = ts_to_ms(ts - self.start_ts, self.time_base).max(0) * FRAMES_PER_MS;
        }
        let samples = out.samples() * CHANNELS;
        let data: &[f32] = out.plane(0);
        self.buf.extend(&data[..samples.min(data.len())]);
        Ok(())
    }
}

impl Drop for AudioReader {
    fn drop(&mut self) {
        crate::diagnostics::audio_decoder_opened(-1);
    }
}

/// Peak loudness of [path] in [buckets] equal slices, each 0.0 to 1.0.
pub fn waveform(path: &str, buckets: usize) -> Result<Vec<f32>> {
    let mut reader = AudioReader::open(path)?;
    let info = super::probe::probe(path)?;
    let total_frames = (info.duration_ms.max(1) * FRAMES_PER_MS) as usize;
    let per_bucket = (total_frames / buckets.max(1)).max(1);
    let mut peaks = vec![0f32; buckets];
    let mut chunk = vec![0f32; 4800 * CHANNELS];
    let mut frame_index = 0usize;
    while frame_index < total_frames {
        reader.fill(frame_index as i64, &mut chunk)?;
        for (i, pair) in chunk.chunks_exact(CHANNELS).enumerate() {
            let bucket = ((frame_index + i) / per_bucket).min(buckets - 1);
            let v = pair[0].abs().max(pair[1].abs());
            if v > peaks[bucket] {
                peaks[bucket] = v;
            }
        }
        frame_index += chunk.len() / CHANNELS;
        if reader.finished && reader.buf.is_empty() {
            break;
        }
    }
    Ok(peaks.into_iter().map(|p| p.min(1.0)).collect())
}

#[cfg(test)]
mod tests {
    use super::{waveform, AudioReader, CHANNELS, FRAMES_PER_MS};
    use crate::test_support::fixtures;

    fn energy(samples: &[f32]) -> f32 {
        samples.iter().map(|s| s * s).sum::<f32>() / samples.len() as f32
    }

    #[test]
    fn reads_contiguous_sound_and_silence_after_the_end() {
        let mut reader = AudioReader::open(&fixtures().tone).unwrap();
        let mut block = vec![0f32; 1024 * CHANNELS];
        let mut at = 100 * FRAMES_PER_MS;
        for _ in 0..20 {
            reader.fill(at, &mut block).unwrap();
            assert!(energy(&block) > 0.001);
            at += 1024;
        }
        // After a seek the first sample is there, not padded silence.
        reader.fill(1500 * FRAMES_PER_MS, &mut block).unwrap();
        assert!(block[..64].iter().any(|s| s.abs() > 0.01));
        reader.fill(5000 * FRAMES_PER_MS, &mut block).unwrap();
        assert!(energy(&block) < 1e-6);
    }

    #[test]
    fn measures_the_loudness_of_a_tone() {
        let peaks = waveform(&fixtures().tone, 50).unwrap();
        assert_eq!(peaks.len(), 50);
        assert!(peaks[10..40].iter().all(|p| *p > 0.05));
    }
}
