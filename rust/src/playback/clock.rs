use std::time::Instant;

/// Playback time: frozen at [base_ms] while paused, running from [started]
/// while playing.
#[derive(Clone, Copy, Debug)]
pub struct Clock {
    base_ms: i64,
    started: Option<Instant>,
}

impl Clock {
    pub fn paused_at(ms: i64) -> Self {
        Self {
            base_ms: ms,
            started: None,
        }
    }

    pub fn playing_from(ms: i64) -> Self {
        Self {
            base_ms: ms,
            started: Some(Instant::now()),
        }
    }

    pub fn is_running(&self) -> bool {
        self.started.is_some()
    }

    pub fn now_ms(&self) -> i64 {
        match self.started {
            Some(t) => self.base_ms + t.elapsed().as_millis() as i64,
            None => self.base_ms,
        }
    }

    /// The position in 48 kHz sample frames, for the audio path.
    pub fn now_frames(&self) -> i64 {
        match self.started {
            Some(t) => self.base_ms * 48 + (t.elapsed().as_micros() as i64 * 48 / 1000),
            None => self.base_ms * 48,
        }
    }
}
