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
- **Every error path is wired**: `FlutterError.onError` (framework errors, non-fatal), `PlatformDispatcher.onError` (fatal), and `runZonedGuarded` around startup (fatal). The startup sets a `stage` key (`database`, `engine`, `settings`, `running`) and leaves breadcrumbs (`app start`, `database open`, `engine load start/ok`, `app ready`), so a fatal report says which step died.
- **Imports and exports log counts and outcomes**, never file paths or project names. A failed export is a non-fatal error with the export settings and the engine's numbers (mean and worst frame, late frames, preview scale) attached as custom keys, and an Analytics `export_failed` event; a finished export is an `export` performance trace with the same dimensions plus `export_finished`.
- **Native crashes** from the Rust engine are captured by `firebase-crashlytics-ndk`, added next to the Flutter plugin.
- **R8 does not rename classes in the beta** (`-dontobfuscate`, `SourceFile`/`LineNumberTable` kept): the console has to show `io.flutter...` and `com.google.firebase...` names, not `hd0.u`. Turn it off once the Crashlytics Gradle plugin uploads the mapping from CI.
- **Firebase App Distribution** is the testing channel: the `testers` group holds `cerberusprogrammer@gmail.com`, and each release carries notes.

## Consequences

- New dependencies, all Firebase: publish them with the project's credentials. `google-services.json` holds only the public client key; there are no service-account secrets in the repository.
- Crashlytics reports take a few minutes to appear; native Rust frames are unsymbolized until native symbol upload is configured, but the module and the Dart breadcrumbs say where.
- Analytics DebugView only shows a device while `adb shell setprop debug.firebase.analytics.app com.cutterapp.cutter` is set; standard reports take up to a day.
- The Firebase project `cutter-video-editor` has Google Analytics linked to the "Default Account for Firebase" property.
- The first reports are in the console: the R8/irondash crash, the Firebase Performance protobuf crash (also fixed with keep rules) and the self-test non-fatal.
