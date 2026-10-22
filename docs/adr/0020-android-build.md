# 0020. Android build

## Status

Accepted · 2026-10-21

## Context

ADR 0008 left Android unbuilt: the machine had no SDK or NDK, and FFmpeg had to be cross-compiled for arm64. This build did both and produced the first APK.

## Decision

- **FFmpeg for Android is built by hand**, LGPL, as static libraries with MediaCodec and JNI (`tool/android/build_ffmpeg.sh`, FFmpeg 8.1.x, the series `ffmpeg-sys-next` 9 targets). `ffmpeg-next` is declared a second time for `cfg(target_os = "android")` with the `static` feature, so Android links `FFMPEG_DIR` statically into `libcutter_engine.so` and no other target changes. `rust/build.rs` links what static FFmpeg needs from Android (`mediandk`, `android`, `atomic`, `m`, `z`).
- **FFmpeg gets the `JavaVM`** from `irondash_engine_context`, which already owns the library's `JNI_OnLoad` (a second one fails to link), in `android::init`, called from `init_app`. Without it the MediaCodec encoder cannot start.
- **`minSdk` is 26.** The engine's sound output (`cpal`) uses AAudio, which exists from Android 8; with the Flutter default (24) the link fails on `-laaudio`.
- **`compileSdk` is 37**, because `permission_handler_android` needs it; AGP 9.1 recommends 36, so `android.suppressUnsupportedCompileSdk=37` is set. The `irondash_engine_context` plugin is compiled against 36 (it declares 31, which the AndroidX libraries it pulls in reject).
- **A shim gives that plugin `project.exec`**, which its bundled cargokit still calls and Gradle 9 removed (`android/build.gradle.kts`). It can go when the plugin ships a cargokit that uses `ExecOperations`.
- **Only arm64-v8a is supported.** The engine and Flutter's engine are built for it alone; the 32-bit and x86 libraries in the APK come from other plugins and are not enough to run.
- **The release APK is signed with the debug key**, which installs on a phone but cannot go to a store.

## Consequences

- Building needs: the Android SDK with platform 37 (and a `platforms/android-37` link to `android-37.0`), build-tools 36, NDK 28.2, a JDK 17 for Gradle (JDK 27 is too new), and `FFMPEG_DIR`. If the JDK does not trust the system certificates, pass `-Djavax.net.ssl.trustStore` to Gradle.
- Not verified: nothing was run on a phone or an emulator. The APK builds, is signed, and its engine library holds `h264_mediacodec`; whether the engine starts, plays, and exports on a device is untested. The JavaVM hand-off and MediaCodec encoding are the likeliest to need fixes.
- The APK is 74 MB, of which the engine library is 45 MB (FFmpeg, the 4.6 MB cutout model and `tract`).
