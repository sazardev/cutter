//! Reading media files through FFmpeg: probing, video frames and audio samples.

pub mod audio;
pub mod probe;
pub mod video;

use std::sync::Once;

use ffmpeg_next as ff;

/// Initialises FFmpeg once per process; every entry point calls it.
pub fn init() {
    static INIT: Once = Once::new();
    INIT.call_once(|| {
        ff::init().expect("FFmpeg failed to initialise");
        // The decoders log every damaged or unreferenced frame at the error
        // level (`mmco: unref short failure` on a seek into the middle of a
        // GOP, thousands of times while scrubbing). They are harmless: a
        // corrupt packet loses one frame and real failures come back as
        // errors, so only fatal messages are printed.
        ff::util::log::set_level(ff::util::log::Level::Fatal);
    });
}

/// A stream timestamp in [time_base] to milliseconds.
pub fn ts_to_ms(ts: i64, time_base: ff::Rational) -> i64 {
    let (num, den) = (time_base.numerator() as i64, time_base.denominator() as i64);
    if den == 0 {
        return 0;
    }
    ts * num * 1000 / den
}

/// Clockwise rotation in degrees stored in the display matrix of a stream.
pub fn stream_rotation(stream: &ff::format::stream::Stream) -> i32 {
    // SAFETY: the codec parameters and their side data live as long as the
    // stream, and the display matrix is nine i32 values when present.
    let degrees = unsafe {
        let par = (*stream.as_ptr()).codecpar;
        let sd = ff::ffi::av_packet_side_data_get(
            (*par).coded_side_data,
            (*par).nb_coded_side_data,
            ff::ffi::AVPacketSideDataType::AV_PKT_DATA_DISPLAYMATRIX,
        );
        if sd.is_null() || (*sd).size < 36 {
            0.0
        } else {
            ff::ffi::av_display_rotation_get((*sd).data as *const i32)
        }
    };
    if degrees.is_nan() {
        return 0;
    }
    // FFmpeg reports counter-clockwise degrees; players rotate clockwise.
    let cw = (-degrees).round() as i32;
    ((cw % 360) + 360) % 360 / 90 * 90
}
