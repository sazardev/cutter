//! Cutter's media engine: decoding, composition, effects, preview playback
//! and export, reached from Flutter through Flutter Rust Bridge.

#[cfg(target_os = "android")]
mod android;
pub mod api;
mod diagnostics;
mod export;
mod frb_generated;
mod media;
mod playback;
mod render;
#[cfg(test)]
mod test_support;
