//! Sends FFmpeg's own log lines to the engine diagnostics.
//!
//! On a phone stderr goes nowhere, so an encode that fails inside MediaCodec
//! left no trace. With this the last lines can be read from the app's
//! Rendimiento panel and copied into a bug report.
#![allow(dead_code)] // only installed on Android; compiled everywhere.

use std::ffi::{c_char, c_int, c_void, CStr};

use ffmpeg_next::ffi;

use crate::diagnostics;

/// What `av_log` calls back with. C's `va_list` is an array on Android and
/// decays to a pointer when passed, so a `*mut c_void` matches it on both
/// ABIs; the bindings name it `__va_list_tag` on x86_64 and `va_list` on
/// arm64, which is why these three are declared here instead.
type AvLogCallback =
    unsafe extern "C" fn(ptr: *mut c_void, level: c_int, fmt: *const c_char, args: *mut c_void);

extern "C" {
    fn av_log_set_callback(callback: Option<AvLogCallback>);
    fn av_log_set_level(level: c_int);
    fn av_log_format_line2(
        ptr: *mut c_void,
        level: c_int,
        fmt: *const c_char,
        args: *mut c_void,
        line: *mut c_char,
        line_size: c_int,
        print_prefix: *mut c_int,
    ) -> c_int;
}

unsafe extern "C" fn forward(
    ptr: *mut c_void,
    level: c_int,
    fmt: *const c_char,
    args: *mut c_void,
) {
    // The decoders log every sample while scrubbing; only warnings and
    // errors are worth keeping in the panel.
    if level & 0xff > ffi::AV_LOG_WARNING {
        return;
    }
    let mut line = [0 as c_char; 1024];
    let mut prefix: c_int = 0;
    // SAFETY: the callback receives a valid va_list from FFmpeg; the buffer
    // and the format come from FFmpeg as well.
    let written = unsafe {
        av_log_format_line2(
            ptr,
            level,
            fmt,
            args,
            line.as_mut_ptr(),
            line.len() as c_int,
            &mut prefix,
        )
    };
    if written <= 0 {
        return;
    }
    // SAFETY: `av_log_format_line2` writes a NUL-terminated string.
    let text = unsafe { CStr::from_ptr(line.as_ptr()) };
    let text = text.to_string_lossy();
    let text = text.trim();
    if text.is_empty() {
        return;
    }
    match level & 0xff {
        l if l <= ffi::AV_LOG_ERROR => diagnostics::error(format!("ffmpeg {text}")),
        l if l <= ffi::AV_LOG_WARNING => diagnostics::warn(format!("ffmpeg {text}")),
        _ => diagnostics::info(format!("ffmpeg {text}")),
    }
}

/// Installs the callback; call once, before FFmpeg logs anything.
pub fn install() {
    // SAFETY: the callback stays valid for the life of the process.
    unsafe {
        av_log_set_callback(Some(forward));
        av_log_set_level(ffi::AV_LOG_WARNING);
    }
}
