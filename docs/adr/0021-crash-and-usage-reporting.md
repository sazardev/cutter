# 0021. Crash, usage and performance reporting

## Status

Accepted · 2026-10-22

## Context

The first Android betas could die before the first frame and leave nothing behind: release Dart errors, R8 `NoSuchMethodError`s and Rust panics all ended as "Cutter keeps stopping" with no report. The emulator's logcat found them, but a tester's phone has no logcat. The product needs to know, from a tester's install, what failed, where in the startup or the export it failed, on which device and with which build.

## Decision

- **Firebase Crashlytics, Analytics and Performance** (`firebase_core`, `firebase_crashlytics`, `firebase_analytics`, `firebase_performance`), configured from `android/app/google-services.json`, which is committed. The Google Services Gradle plugin reads it; the app does not carry the SDK config itself.
- **Telemetry starts before the database and the engine**, because those are the steps that were failing. `startTelemetry` returns a no-op reporter when Firebase is not configured (desktop) or fails, so reporting never keeps the editor closed.
- **Collection is off in debug** unless `--dart-define=TELEMETRY=on`; profile and release send. The beta is release.
- **A random install ID** (`telemetry.install_id` in `app_settings`, UUID v4) is the Crashlytics user ID and the Analytics user ID. It is not a name or an account: it matches the reports of one install across launches. It is also a custom key and a breadcrumb, so the tester can quote it.
- **Every error path is wired**: `FlutterError.onError` (framework errors, non-fatal), `PlatformDispatcher.onError` and `runZonedGuarded` (uncaught errors: fatal only until startup finishes, non-fatal after, with a `handled` key, so the app that is still running does not count as a crash and the crash-free numbers stay true). The startup sets a `stage` key (`database`, `engine`, `settings`, `running`) and leaves breadcrumbs (`app start`, `database open`, `engine load start/ok`, `app ready`), so a fatal report says which step died.
- **Imports and exports log counts and outcomes**, never file paths or project names. A failed export is a non-fatal error with the export settings and the engine's numbers (mean and worst frame, late frames, preview scale) attached as custom keys, and an Analytics `export_failed` event; a finished export is an `export` performance trace with the same dimensions plus `export_finished`.
- **Native crashes** from the Rust engine are captured by `firebase-crashlytics-ndk`, added next to the Flutter plugin. The Crashlytics Gradle plugin uploads the native symbols from the unstripped libraries (`nativeSymbolUploadEnabled`), and the Rust release profile keeps `line-tables-only`, so a frame names the function, file and line.
- **A rust panic on an engine thread** (preview, mixer, audio) kills that thread only and on Android stderr goes nowhere. A panic hook writes it to the engine log (`... E thread 'x' panicked at file:line: message`); `EngineWatch` reads the log every 10 s and reports each panic as a non-fatal `EnginePanic`, plus every error line as a breadcrumb.
- **State on every report**: custom keys `channel` (`beta` in release, `dev` otherwise, or `--dart-define=CHANNEL=`), `project` (layers, clips, canvas and length: counts only), the engine's counters (`engine_late_frames`, `engine_cache_mb`, `engine_preview_scale`, decoders) and `process_rss_mb`, refreshed by `EngineWatch` only when a value changes. Each edit of the editor is a breadcrumb (`edit 12:00:01.123 split 4ms ok`); no names, paths or typed text.
- **A non-fatal error repeats at most once a minute** (`ErrorThrottle`, keyed by type and first stack frame): a widget that throws on every frame would otherwise fill Crashlytics' few non-fatal slots per session. Fatal errors are never held back.
- **R8 does not rename classes in the beta** (`-dontobfuscate`, `SourceFile`/`LineNumberTable` kept): the console has to show `io.flutter...` and `com.google.firebase...` names, not `hd0.u`. The Crashlytics Gradle plugin now uploads the mapping on every release build, so `-dontobfuscate` can go once a build has shown the mapping arriving in the console.
- **Firebase App Distribution** is the testing channel: the `testers` group holds `cerberusprogrammer@gmail.com`, and each release carries notes.

## Consequences

- New dependencies, all Firebase: publish them with the project's credentials. `google-services.json` holds only the public client key; there are no service-account secrets in the repository.
- Crashlytics reports take a few minutes to appear. A release build uploads the mapping and the native symbols, so it needs network and the `google-services.json` project; a build without network fails at the upload task.
- ANRs are reported by Crashlytics on Android 11 and later only.
- The Dart stack traces are readable because release builds do not use `--split-debug-info`; if that is turned on, upload the symbols with `firebase crashlytics:symbols:upload`.
- A separate Firebase app for debug builds (an `applicationIdSuffix`) needs its own entry in `google-services.json`; until then the `channel` key keeps developer reports apart.
- Analytics DebugView only shows a device while `adb shell setprop debug.firebase.analytics.app com.cutterapp.cutter` is set; standard reports take up to a day.
- The Firebase project `cutter-video-editor` has Google Analytics linked to the "Default Account for Firebase" property.
- The first reports are in the console: the R8/irondash crash, the Firebase Performance protobuf crash (also fixed with keep rules) and the self-test non-fatal.
