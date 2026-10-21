use crate::api::types::TimelineClip;

/// An affine colour transform: each output channel is a weighted sum of the
/// input channels plus an offset, on the 0..255 scale.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ColorMatrix(pub [[f32; 4]; 3]);

const IDENTITY: ColorMatrix = ColorMatrix([
    [1.0, 0.0, 0.0, 0.0],
    [0.0, 1.0, 0.0, 0.0],
    [0.0, 0.0, 1.0, 0.0],
]);
const LUMA: [f32; 3] = [0.2126, 0.7152, 0.0722];

impl ColorMatrix {
    /// Applies [self] after [first].
    fn after(&self, first: &ColorMatrix) -> ColorMatrix {
        let (a, b) = (&self.0, &first.0);
        let mut m = [[0.0; 4]; 3];
        for r in 0..3 {
            for c in 0..3 {
                m[r][c] = a[r][0] * b[0][c] + a[r][1] * b[1][c] + a[r][2] * b[2][c];
            }
            m[r][3] = a[r][0] * b[0][3] + a[r][1] * b[1][3] + a[r][2] * b[2][3] + a[r][3];
        }
        ColorMatrix(m)
    }

    fn saturation(s: f32) -> ColorMatrix {
        let mut m = [[0.0; 4]; 3];
        for (r, row) in m.iter_mut().enumerate() {
            for c in 0..3 {
                row[c] = (1.0 - s) * LUMA[c] + if r == c { s } else { 0.0 };
            }
        }
        ColorMatrix(m)
    }

    fn scale_offset(scale: [f32; 3], offset: [f32; 3]) -> ColorMatrix {
        ColorMatrix([
            [scale[0], 0.0, 0.0, offset[0]],
            [0.0, scale[1], 0.0, offset[1]],
            [0.0, 0.0, scale[2], offset[2]],
        ])
    }

    fn blend(&self, other: &ColorMatrix, amount: f32) -> ColorMatrix {
        let mut m = self.0;
        for (r, row) in m.iter_mut().enumerate() {
            for (c, v) in row.iter_mut().enumerate() {
                *v = *v * (1.0 - amount) + other.0[r][c] * amount;
            }
        }
        ColorMatrix(m)
    }

    fn filter(id: &str) -> ColorMatrix {
        match id {
            "mono" => Self::saturation(0.0),
            "warm" => Self::scale_offset([1.08, 1.0, 0.86], [10.0, 3.0, -8.0]),
            "cool" => Self::scale_offset([0.88, 1.0, 1.08], [-8.0, 0.0, 12.0]),
            "vintage" => {
                let sepia = ColorMatrix([
                    [0.393, 0.769, 0.189, 0.0],
                    [0.349, 0.686, 0.168, 0.0],
                    [0.272, 0.534, 0.131, 0.0],
                ]);
                let faded = Self::scale_offset([0.85, 0.85, 0.85], [24.0, 20.0, 14.0]);
                faded.after(&IDENTITY.blend(&sepia, 0.65))
            }
            _ => IDENTITY,
        }
    }

    /// The transform for [clip]: its filter first, then its adjustments.
    /// None when the clip leaves colours untouched.
    pub fn for_clip(clip: &TimelineClip) -> Option<ColorMatrix> {
        let mut m = clip.filter.as_deref().map(Self::filter).unwrap_or(IDENTITY);
        if clip.saturation != 0.0 {
            m = Self::saturation(1.0 + clip.saturation).after(&m);
        }
        if clip.contrast != 0.0 {
            let c = 1.0 + clip.contrast;
            m = Self::scale_offset([c; 3], [128.0 * (1.0 - c); 3]).after(&m);
        }
        if clip.brightness != 0.0 {
            m = Self::scale_offset([1.0; 3], [clip.brightness * 96.0; 3]).after(&m);
        }
        (m != IDENTITY).then_some(m)
    }

    /// Fixed-point form for the per-pixel loop.
    pub fn fixed(&self) -> [[i32; 4]; 3] {
        self.0.map(|row| row.map(|v| (v * 1024.0).round() as i32))
    }
}

#[inline]
pub fn apply_fixed(m: &[[i32; 4]; 3], r: u8, g: u8, b: u8) -> (u8, u8, u8) {
    let (r, g, b) = (i32::from(r), i32::from(g), i32::from(b));
    let ch = |row: &[i32; 4]| {
        ((row[0] * r + row[1] * g + row[2] * b + row[3]) >> 10).clamp(0, 255) as u8
    };
    (ch(&m[0]), ch(&m[1]), ch(&m[2]))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::types::EngineMediaKind;

    fn clip() -> TimelineClip {
        TimelineClip {
            path: String::new(),
            kind: EngineMediaKind::Video,
            start_ms: 0,
            in_ms: 0,
            out_ms: 1000,
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
        }
    }

    #[test]
    fn untouched_clip_has_no_matrix() {
        assert!(ColorMatrix::for_clip(&clip()).is_none());
    }

    #[test]
    fn mono_makes_every_channel_equal() {
        let m = ColorMatrix::for_clip(&TimelineClip {
            filter: Some("mono".into()),
            ..clip()
        })
        .unwrap()
        .fixed();
        let (r, g, b) = apply_fixed(&m, 200, 40, 90);
        assert!(r.abs_diff(g) <= 1 && g.abs_diff(b) <= 1);
    }

    #[test]
    fn brightness_raises_every_channel() {
        let m = ColorMatrix::for_clip(&TimelineClip {
            brightness: 0.5,
            ..clip()
        })
        .unwrap()
        .fixed();
        let (r, g, b) = apply_fixed(&m, 100, 100, 100);
        assert!(r > 100 && g > 100 && b > 100);
    }
}
