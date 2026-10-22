//! Entrance and exit animations of a clip. An animation turns the progress
//! of its span (0 at the start, 1 at the end) into a change of the clip's
//! placement; at progress 1 of an entrance, and 0 of an exit, it is the
//! identity.

/// Every animation id the engine renders; the editor lists the same ids (a
/// Dart test compares both).
#[cfg(test)]
pub const ANIMATION_IDS: &[&str] = &[
    "fade",
    "slide_left",
    "slide_right",
    "slide_up",
    "slide_down",
    "zoom_in",
    "zoom_out",
    "spin",
    "pop",
];

/// A change applied on top of a clip's placement.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Anim {
    /// Offset as a fraction of the canvas width / height.
    pub dx: f32,
    pub dy: f32,
    /// Multiplies the size.
    pub scale: f32,
    /// Added to the clockwise rotation, in degrees.
    pub rotation: f32,
    /// Multiplies the opacity.
    pub opacity: f32,
}

impl Anim {
    pub const NONE: Anim = Anim {
        dx: 0.0,
        dy: 0.0,
        scale: 1.0,
        rotation: 0.0,
        opacity: 1.0,
    };

    /// The change [id] makes while a clip comes in: [p] is 0 as it starts
    /// and 1 once it is in place. Unknown ids change nothing.
    pub fn enter(id: &str, p: f32) -> Anim {
        let p = p.clamp(0.0, 1.0);
        let away = 1.0 - ease_out(p);
        match id {
            "fade" => Anim {
                opacity: ease_out(p),
                ..Anim::NONE
            },
            "slide_left" => Anim {
                dx: -away,
                ..Anim::NONE
            },
            "slide_right" => Anim {
                dx: away,
                ..Anim::NONE
            },
            "slide_up" => Anim {
                dy: -away,
                ..Anim::NONE
            },
            "slide_down" => Anim {
                dy: away,
                ..Anim::NONE
            },
            "zoom_in" => Anim {
                scale: 0.4 + 0.6 * ease_out(p),
                opacity: ease_out(p),
                ..Anim::NONE
            },
            "zoom_out" => Anim {
                scale: 1.6 - 0.6 * ease_out(p),
                opacity: ease_out(p),
                ..Anim::NONE
            },
            "spin" => Anim {
                scale: 0.3 + 0.7 * ease_out(p),
                rotation: -180.0 * away,
                opacity: ease_out(p),
                ..Anim::NONE
            },
            "pop" => Anim {
                scale: ease_back(p),
                ..Anim::NONE
            },
            _ => Anim::NONE,
        }
    }

    /// The change [id] makes while a clip goes out: [p] is 0 as it starts
    /// to leave and 1 at its last moment. It is the entrance played
    /// backwards, so a clip leaves the way it came.
    pub fn exit(id: &str, p: f32) -> Anim {
        Anim::enter(id, 1.0 - p.clamp(0.0, 1.0))
    }

    /// Both changes at once, for a clip short enough that they overlap.
    pub fn then(self, other: Anim) -> Anim {
        Anim {
            dx: self.dx + other.dx,
            dy: self.dy + other.dy,
            scale: self.scale * other.scale,
            rotation: self.rotation + other.rotation,
            opacity: self.opacity * other.opacity,
        }
    }
}

/// The animation of a clip that lasts [duration_ms], [t] ms after it began:
/// its entrance over the first [in_ms] and its exit over the last [out_ms].
/// Spans that would overlap are shortened so each gets its share.
pub fn at(
    enter: Option<&str>,
    in_ms: i64,
    exit: Option<&str>,
    out_ms: i64,
    duration_ms: i64,
    t: i64,
) -> Anim {
    let (mut in_ms, mut out_ms) = (in_ms.max(0), out_ms.max(0));
    if in_ms + out_ms > duration_ms && in_ms + out_ms > 0 {
        let k = duration_ms as f64 / (in_ms + out_ms) as f64;
        in_ms = (in_ms as f64 * k) as i64;
        out_ms = (out_ms as f64 * k) as i64;
    }
    let mut anim = Anim::NONE;
    if let Some(id) = enter.filter(|_| in_ms > 0 && t < in_ms) {
        anim = anim.then(Anim::enter(id, t as f32 / in_ms as f32));
    }
    let left = duration_ms - t;
    if let Some(id) = exit.filter(|_| out_ms > 0 && left <= out_ms) {
        anim = anim.then(Anim::exit(id, 1.0 - left as f32 / out_ms as f32));
    }
    anim
}

fn ease_out(p: f32) -> f32 {
    1.0 - (1.0 - p).powi(3)
}

/// Overshoots 1 on the way, then settles.
fn ease_back(p: f32) -> f32 {
    let (c1, c3) = (1.70158_f32, 2.70158_f32);
    let q = p - 1.0;
    1.0 + c3 * q.powi(3) + c1 * q.powi(2)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_animation_ends_in_place() {
        for id in ANIMATION_IDS {
            let a = Anim::enter(id, 1.0);
            assert!(
                (a.scale - 1.0).abs() < 1e-4 && a.dx.abs() < 1e-4 && a.opacity > 0.999,
                "{id} does not settle: {a:?}"
            );
            assert!(Anim::enter(id, 0.0) != Anim::NONE, "{id} does nothing at 0");
        }
    }

    #[test]
    fn unknown_ids_change_nothing() {
        assert_eq!(Anim::enter("nope", 0.2), Anim::NONE);
    }

    #[test]
    fn fade_starts_invisible() {
        assert_eq!(Anim::enter("fade", 0.0).opacity, 0.0);
    }

    #[test]
    fn slides_start_off_to_their_side() {
        assert!(Anim::enter("slide_left", 0.0).dx < 0.0);
        assert!(Anim::enter("slide_right", 0.0).dx > 0.0);
        assert!(Anim::enter("slide_up", 0.0).dy < 0.0);
        assert!(Anim::enter("slide_down", 0.0).dy > 0.0);
    }

    #[test]
    fn pop_overshoots_before_it_settles() {
        assert!(Anim::enter("pop", 0.7).scale > 1.0);
    }

    #[test]
    fn exit_is_the_entrance_played_backwards() {
        assert_eq!(Anim::exit("fade", 0.0), Anim::NONE);
        assert_eq!(Anim::exit("fade", 1.0).opacity, 0.0);
    }

    #[test]
    fn a_clip_is_untouched_between_its_animations() {
        let a = at(Some("fade"), 500, Some("fade"), 500, 4000, 2000);
        assert_eq!(a, Anim::NONE);
    }

    #[test]
    fn a_clip_fades_in_then_out() {
        let first = at(Some("fade"), 500, Some("fade"), 500, 4000, 0);
        let last = at(Some("fade"), 500, Some("fade"), 500, 4000, 3999);
        assert_eq!(first.opacity, 0.0);
        assert!(last.opacity < 0.01);
        assert!(at(Some("fade"), 500, None, 0, 4000, 250).opacity < 1.0);
    }

    #[test]
    fn overlapping_spans_share_a_short_clip() {
        let mid = at(Some("fade"), 800, Some("fade"), 800, 1000, 500);
        assert!(
            mid.opacity > 0.9,
            "the middle of a short clip is nearly full"
        );
    }

    #[test]
    fn no_animation_means_none() {
        assert_eq!(at(None, 500, None, 500, 4000, 0), Anim::NONE);
    }
}
