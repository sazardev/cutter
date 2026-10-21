import 'package:cutter/app/app.dart';
import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/core/engine/media_engine.dart';
import 'package:cutter/core/engine/rust_media_engine.dart';
import 'package:cutter/core/settings/settings_store.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/home/data/drift_home_preferences_repository.dart';
import 'package:cutter/features/home/presentation/home_providers.dart';
import 'package:cutter/features/settings/data/drift_appearance_repository.dart';
import 'package:cutter/features/settings/data/drift_export_preferences_repository.dart';
import 'package:cutter/features/settings/presentation/appearance_providers.dart';
import 'package:cutter/features/settings/presentation/export_preferences_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = _openDatabaseOrStop();
  // Every picture and sound goes through the Rust engine; without it the
  // editor has nothing to show, so a load failure stops the app.
  final engine = await RustMediaEngine.load();
  // Read before the first frame so the app opens already in the saved look.
  final settingsStore = SettingsStore(database);
  final appearance = await DriftAppearanceRepository(settingsStore).load();
  final exportPreferences =
      await DriftExportPreferencesRepository(settingsStore).load();
  final homePreferences =
      await DriftHomePreferencesRepository(settingsStore).load();
  runApp(
    ProviderScope(
      overrides: [
        initialAppearanceProvider.overrideWithValue(appearance),
        initialHomePreferencesProvider.overrideWithValue(homePreferences),
        initialExportPreferencesProvider.overrideWithValue(exportPreferences),
        appDatabaseProvider.overrideWithValue(database),
        mediaEngineProvider.overrideWithValue(engine),
      ],
      child: const CutterApp(),
    ),
  );
}
