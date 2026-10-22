# 0020. Android build

## Status

Accepted · 2026-10-21 · updated after the first run on a device

## Context

ADR 0008 left Android unbuilt: the machine had no SDK or NDK, and FFmpeg had to be cross-compiled for arm64. This build did both and produced the first APK. It was afterwards run on an Android 13 (API 33) x86_64 emulator, which turned up the export stall described below.

## Decision

- **FFmpeg for Android is built by hand**, LGPL, as static libraries with MediaCodec and JNI (`tool/android/build_ffmpeg.sh`, FFmpeg 8.1.x, the series `ffmpeg-sys-next` 9 targets). `ffmpeg-next` is declared a second time for `cfg(target_os = "android")` with the `static` feature, so Android links `FFMPEG_DIR` statically into `libcutter_engine.so` and no other target changes. `rust/build.rs` links what static FFmpeg needs from Android (`mediandk`, `android`, `atomic`, `m`, `z`).
- **FFmpeg gets the `JavaVM`** from `irondash_engine_context`, which already owns the library's `JNI_OnLoad` (a second one fails to link), in `android::init`, called from `init_app`. Without a VM FFmpeg falls back to the NDK `AMediaCodec` path, which also encodes; with one it uses the JNI path, which is the one phones and the emulator were tested with.
- **`minSdk` is 26.** The engine's sound output (`cpal`) uses AAudio, which exists from Android 8; with the Flutter default (24) the link fails on `-laaudio`.
- **`compileSdk` is 37**, because `permission_handler_android` needs it; AGP 9.1 recommends 36, so `android.suppressUnsupportedCompileSdk=37` is set. The `irondash_engine_context` plugin is compiled against 36 (it declares 31, which the AndroidX libraries it pulls in reject).
- **A shim gives that plugin `project.exec`**, which its bundled cargokit still calls and Gradle 9 removed (`android/build.gradle.kts`). It can go when the plugin ships a cargokit that uses `ExecOperations`.
- **two ABIs are supported: arm64-v8a and x86_64.** `tool/android/build_ffmpeg.sh` takes the ABI, and each ABI gets its own `FFMPEG_DIR` prefix and its own build (`--target-platform android-arm64` or `android-x64`): `FFMPEG_DIR` points at one architecture, so the two are never built in the same run. x86_64 is for the emulator. The 32-bit targets do not build (`ffmpeg-sys-next`'s i686 bindings fail on a Vulkan header assert) and could not run, so cargokit's debug build filters them out (`rust_builder/cargokit/gradle/plugin.gradle`) and `flutter run` works on the two supported ABIs.
- **the APK that ships has both ABIs, and no 32-bit libs.** A single-ABI build is a trap: the plugins still bundle their own `armeabi-v7a` and `x86_64` libraries (`libdartjni`, `libsqlite3`), so `aapt` reports those ABIs and the installer accepts the APK on an x86_64 emulator, where `libflutter.so` and `libcutter_engine.so` are missing and the app closes at launch. The two release APKs are merged into one universal APK (arm64 + x86_64, `armeabi-v7a` stripped), aligned and signed with the debug key, and that is what App Distribution gets.
- **MediaCodec does not get `AV_CODEC_FLAG_GLOBAL_HEADER`.** With it FFmpeg builds the extradata at open by sending a dummy frame, signalling end of stream and flushing the codec; after that flush the Android encoder never hands out an input buffer again and the export dies with `EAGAIN` after five seconds. Without the flag the MP4 muxer takes the SPS/PPS from the first packet, and the file is valid. The encoder also gets NV12 before planar YUV420P (some devices advertise planar and then stall), and `EAGAIN` from `send_frame` drains packets and retries instead of failing the export.
- **R8 keeps `io.flutter.**` and `dev.irondash.**`** (`android/app/proguard-rules.pro`). Release builds are minified (Flutter's Gradle plugin sets `isMinifyEnabled = true`) and R8 renamed `io.flutter.view.TextureRegistry`; `libirondash_engine_context_native.so` looks the plugin method up by JNI signature (`getTextureRegistry(J)Lio/flutter/view/TextureRegistry;`) and the app died at launch with `NoSuchMethodError`. Profile builds do not shrink, which is why the emulator run looked fine until the release APK was installed.
- **The release APK is signed with the debug key**, which installs on a phone but cannot go to a store. The beta goes out through Firebase App Distribution.

## Consequences

- Building needs: the Android SDK with platform 37 (and a `platforms/android-37` link to `android-37.0`), build-tools 36, NDK 28.2, a JDK 17 for Gradle (JDK 27 is too new), and `FFMPEG_DIR`. If the JDK does not trust the system certificates, pass `-Djavax.net.ssl.trustStore` to Gradle. A 15 GB machine needs `org.gradle.jvmargs=-Xmx3G` and `CARGO_BUILD_JOBS=6` to build while the emulator runs. The arm64 build also needs `BINDGEN_EXTRA_CLANG_ARGS="--target=aarch64-linux-android26 --sysroot=<ndk>/toolchains/llvm/prebuilt/linux-x86_64/sysroot"`, or `ffmpeg-sys-next`'s bindgen picks the host's glibc headers and fails on `__float128`.
- Verified on the emulator: the app starts, imports a 1080 × 1920 H.264 video, draws the preview through the engine texture, plays it, and exports a 1080 × 1920 30 fps MP4 (H.264 + AAC, 240 frames, decoded clean by ffprobe/ffmpeg on the host). Export of 8 s took about 10 s under the emulator's software encoder.
- Not verified: a physical arm64 phone. The arm64 FFmpeg is built with the same script and flags as the x86_64 one, but MediaCodec, AAudio and the JavaVM hand-off only run on real hardware.
- The APK is 152 MB in profile with the x86_64 engine (the engine library alone is ~52 MB, with FFmpeg, the cutout model and `tract`); the arm64 release is smaller.
