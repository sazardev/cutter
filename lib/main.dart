import 'dart:async';

import 'package:cutter/app/app.dart';
import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/core/engine/media_engine.dart';
import 'package:cutter/core/engine/rust_media_engine.dart';
import 'package:cutter/core/settings/settings_store.dart';
import 'package:cutter/core/telemetry/engine_watch.dart';
import 'package:cutter/core/telemetry/firebase_telemetry.dart';
import 'package:cutter/core/telemetry/install_id.dart';
import 'package:cutter/core/telemetry/telemetry.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/home/data/drift_home_preferences_repository.dart';
import 'package:cutter/features/home/presentation/home_providers.dart';
import 'package:cutter/features/settings/data/drift_appearance_repository.dart';
import 'package:cutter/features/settings/data/drift_export_preferences_repository.dart';
import 'package:cutter/features/settings/presentation/appearance_providers.dart';
import 'package:cutter/features/settings/presentation/export_preferences_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether crashes, usage and performance are sent. Off in debug builds
/// unless `--dart-define=TELEMETRY=on`; on in profile and release.
const bool _telemetryEnabled = !kDebugMode || bool.fromEnvironment('TELEMETRY');

/// The reporter the startup code uses; replaced as soon as Firebase starts.
Telemetry _telemetry = const NoopTelemetry();

/// Whether startup finished and the editor is about to show. Before it, an
/// uncaught error means the app could not start (fatal); after it the app is
/// still running, so the same error is a non-fatal report and the crash-free
/// numbers stay true.
bool _booted = false;

/// Reports an error nobody caught: fatal only while the app is starting.
void _reportUncaught(Object error, StackTrace stack, String stage) {
  unawaited(
    _telemetry.recordError(
      error,
      stack,
      reason: 'uncaught error',
      fatal: !_booted,
      keys: {'stage': stage, 'handled': _booted},
    ),
  );
}

/// Opens the database or stops with a clear message: the editor cannot work
/// without its source of truth.
AppDatabase _openDatabaseOrStop() {
  try {
    return openAppDatabase();
  } on Object catch (error, stackTrace) {
    Error.throwWithStackTrace(
      StateError('Could not open the local database: $error'),
      stackTrace,
    );
  }
}

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      _telemetry = await startTelemetry(enabled: _telemetryEnabled);
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        unawaited(
          _telemetry.recordError(
            details.exception,
            details.stack,
            reason: details.library,
            keys: {'stage': 'widget'},
          ),
        );
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        _reportUncaught(error, stack, 'platform');
        return true;
      };
      await _start();
    },
    (error, stack) {
      _reportUncaught(error, stack, _booted ? 'zone' : 'startup');
      debugPrint('Uncaught error: $error\n$stack');
    },
  );
}

Future<void> _start() async {
  _telemetry.log('app start (telemetry ${_telemetry.enabled ? 'on' : 'off'})');
  _telemetry.setKey('stage', 'database');
  final database = _openDatabaseOrStop();
  final settingsStore = SettingsStore(database);

  // The same random ID in every report, so a crash can be matched to the
  // tester who saw it without storing a name or an account.
  final installId = await loadInstallId(settingsStore);
  await _telemetry.identify(installId);
  _telemetry
    ..setKey('stage', 'engine')
    ..log('database open, install $installId');

  // Every picture and sound goes through the Rust engine; without it the
  // editor has nothing to show, so a load failure stops the app.
  final engineTrace = _telemetry.startTrace('engine_load');
  _telemetry.log('engine load start');
  final engine = await RustMediaEngine.load();
  await engineTrace.stop();
  _telemetry
    ..log('engine load ok')
    ..setKey('stage', 'settings');
  // Read before the first frame so the app opens already in the saved look.
  final appearance = await DriftAppearanceRepository(settingsStore).load();
  final exportPreferences =
      await DriftExportPreferencesRepository(settingsStore).load();
  final homePreferences =
      await DriftHomePreferencesRepository(settingsStore).load();

  _booted = true;
  EngineWatch(engine: engine, telemetry: _telemetry).start();
  _telemetry
    ..setKey('stage', 'running')
    ..log('app ready');
  unawaited(_telemetry.event('app_opened'));

  runApp(
    ProviderScope(
      overrides: [
        initialAppearanceProvider.overrideWithValue(appearance),
        initialHomePreferencesProvider.overrideWithValue(homePreferences),
        initialExportPreferencesProvider.overrideWithValue(exportPreferences),
        appDatabaseProvider.overrideWithValue(database),
        mediaEngineProvider.overrideWithValue(engine),
        telemetryProvider.overrideWithValue(_telemetry),
      ],
      child: const CutterApp(),
    ),
  );
}
