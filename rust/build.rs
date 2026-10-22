//! Links what a static FFmpeg needs from Android itself.

fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android") {
        // `mediandk` and `android` are the MediaCodec and window libraries
        // FFmpeg's `--enable-mediacodec` build calls; `atomic`, `m` and `z`
        // are its runtime and zlib.
        for lib in ["atomic", "m", "z", "android", "mediandk"] {
            println!("cargo:rustc-link-lib={lib}");
        }
    }
}
