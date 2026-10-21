use std::collections::{HashMap, HashSet};

use super::compositor::{reader_key, reader_keys};
use crate::api::types::{EngineMediaKind, Timeline};
use crate::media::audio::{AudioReader, CHANNELS, FRAMES_PER_MS};

/// Mixes the sound of every audible clip of a timeline into 48 kHz stereo.
#[derive(Default)]
pub struct Mixer {
    readers: HashMap<String, AudioReader>,
    silent: HashSet<String>,
    scratch: Vec<f32>,
}

impl Mixer {
    /// Drops the readers of files the timeline no longer uses.
    pub fn retain(&mut self, timeline: &Timeline) {
        let used = reader_keys(timeline);
        self.readers.retain(|key, _| used.contains(key));
        self.silent.retain(|key| used.contains(key));
    }

    /// Fills [out] (interleaved stereo) with the timeline sound starting at
    /// sample frame [from] of the timeline.
    pub fn mix(&mut self, timeline: &Timeline, from: i64, out: &mut [f32]) {
        out.fill(0.0);
        let to = from + (out.len() / CHANNELS) as i64;
        for (index, layer) in timeline.layers.iter().enumerate() {
            if layer.muted || layer.volume <= 0.0 || layer.kind == EngineMediaKind::Image {
                continue;
            }
            for clip in &layer.clips {
                // Reversed sound is not played back (SPEC Q13), nor sound at
                // another speed until pitch-correct stretching exists.
                if clip.reversed || clip.volume <= 0.0 || (clip.rate() - 1.0).abs() > 1e-3 {
                    continue;
                }
                let start = clip.start_ms * FRAMES_PER_MS;
                let end = clip.end_ms() * FRAMES_PER_MS;
                let (a, b) = (from.max(start), to.min(end));
                if a >= b {
                    continue;
                }
                let key = reader_key(index, &clip.path);
                if self.silent.contains(&key) {
                    continue;
                }
                if !self.readers.contains_key(&key) {
                    match AudioReader::open(&clip.path) {
                        Ok(reader) => {
                            self.readers.insert(key.clone(), reader);
                        }
                        Err(_) => {
                            self.silent.insert(key);
                            continue;
                        }
                    }
                }
                let reader = self.readers.get_mut(&key).unwrap();
                let n = ((b - a) as usize) * CHANNELS;
                self.scratch.resize(n, 0.0);
                let source = clip.in_ms * FRAMES_PER_MS + (a - start);
                if reader.fill(source, &mut self.scratch).is_err() {
                    continue;
                }
                let gain = layer.volume * clip.volume;
                let offset = ((a - from) as usize) * CHANNELS;
                let fade_in = clip.fade_in_ms.max(0) * FRAMES_PER_MS;
                let fade_out = clip.fade_out_ms.max(0) * FRAMES_PER_MS;
                if fade_in == 0 && fade_out == 0 {
                    for (o, s) in out[offset..offset + n].iter_mut().zip(&self.scratch) {
                        *o += s * gain;
                    }
                } else {
                    // Linear ramps at both ends of the clip, per sample frame.
                    for (i, pair) in self.scratch.chunks_exact(CHANNELS).enumerate() {
                        let f = a + i as i64;
                        let mut g = 1.0f32;
                        if fade_in > 0 && f - start < fade_in {
                            g = g.min((f - start) as f32 / fade_in as f32);
                        }
                        if fade_out > 0 && end - f < fade_out {
                            g = g.min((end - f) as f32 / fade_out as f32);
                        }
                        let o = offset + i * CHANNELS;
                        for c in 0..CHANNELS {
                            out[o + c] += pair[c] * gain * g.max(0.0);
                        }
                    }
                }
            }
        }
        for s in out.iter_mut() {
            *s = s.clamp(-1.0, 1.0);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::Mixer;
    use crate::api::types::EngineMediaKind;
    use crate::test_support::{clip, fixtures, layer, vertical};

    #[test]
    fn mixes_audible_clips_and_skips_muted_layers() {
        let f = fixtures();
        let mut timeline = vertical(vec![layer(
            EngineMediaKind::Audio,
            vec![clip(&f.tone, EngineMediaKind::Audio, 0, 0, 2000)],
        )]);
        let mut mixer = Mixer::default();
        let mut out = vec![0f32; 2048];
        mixer.mix(&timeline, 48 * 500, &mut out);
        assert!(out.iter().any(|s| s.abs() > 0.05));
        timeline.layers[0].muted = true;
        mixer.mix(&timeline, 48 * 500, &mut out);
        assert!(out.iter().all(|s| *s == 0.0));
    }

    #[test]
    fn is_silent_outside_every_clip() {
        let f = fixtures();
        let timeline = vertical(vec![layer(
            EngineMediaKind::Audio,
            vec![clip(&f.tone, EngineMediaKind::Audio, 1000, 0, 500)],
        )]);
        let mut out = vec![1f32; 2048];
        Mixer::default().mix(&timeline, 0, &mut out);
        assert!(out.iter().all(|s| *s == 0.0));
    }

    #[test]
    fn fades_start_and_end_in_silence() {
        let f = fixtures();
        let mut c = clip(&f.tone, EngineMediaKind::Audio, 0, 0, 2000);
        c.fade_in_ms = 500;
        c.fade_out_ms = 500;
        let timeline = vertical(vec![layer(EngineMediaKind::Audio, vec![c])]);
        let mut mixer = Mixer::default();
        let peak = |mixer: &mut Mixer, at_ms: i64| {
            let mut out = vec![0f32; 96 * 2];
            mixer.mix(&timeline, at_ms * 48, &mut out);
            out.iter().fold(0f32, |m, s| m.max(s.abs()))
        };
        let early = peak(&mut mixer, 10);
        let middle = peak(&mut mixer, 1000);
        let late = peak(&mut mixer, 1990);
        assert!(early < middle * 0.1, "{early} vs {middle}");
        assert!(late < middle * 0.1, "{late} vs {middle}");
    }

    #[test]
    fn sound_at_another_speed_is_silent() {
        let f = fixtures();
        let mut c = clip(&f.tone, EngineMediaKind::Audio, 0, 0, 2000);
        c.speed = 2.0;
        let timeline = vertical(vec![layer(EngineMediaKind::Audio, vec![c])]);
        let mut out = vec![1f32; 2048];
        Mixer::default().mix(&timeline, 48 * 300, &mut out);
        assert!(out.iter().all(|s| *s == 0.0));
    }
}
