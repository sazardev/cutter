import 'dart:io';

import 'package:cutter/core/settings/settings_store.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/settings/data/drift_export_preferences_repository.dart';
import 'package:cutter/features/settings/domain/export_preferences.dart';
import 'package:cutter/features/settings/domain/export_preferences_repository.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The domain port for the export preferences, backed by drift.
final exportPreferencesRepositoryProvider =
    Provider<ExportPreferencesRepository>(
  (ref) => DriftExportPreferencesRepository(
    SettingsStore(ref.watch(appDatabaseProvider)),
  ),
);

/// The preferences read before the first frame; `main` overrides it.
final initialExportPreferencesProvider = Provider<ExportPreferences>(
  (ref) => const ExportPreferences(),
);

/// Where and how exports are saved; each change is saved at once.
final exportPreferencesProvider =
    NotifierProvider<ExportPreferencesController, ExportPreferences>(
  ExportPreferencesController.new,
);

/// Holds the export preferences and persists each change.
class ExportPreferencesController extends Notifier<ExportPreferences> {
  @override
  ExportPreferences build() => ref.watch(initialExportPreferencesProvider);

  /// Replaces the preferences with [change] applied and saves them.
  Future<void> update(
    ExportPreferences Function(ExportPreferences current) change,
  ) async {
    final next = change(state);
    if (next == state) return;
    state = next;
    try {
      await ref.read(exportPreferencesRepositoryProvider).save(next);
    } on Object catch (error) {
      // The choice holds for this session; only persistence is lost.
      debugPrint('Could not save the export preferences: $error');
    }
  }
}

/// Asks the user for a folder; null when they cancel. Tests replace it.
final directoryPickerProvider = Provider<Future<String?> Function()>(
  (ref) => FilePicker.getDirectoryPath,
);

/// Whether files can be written into [directory]: it is created when needed
/// and a probe file is written and removed.
Future<bool> isWritableDirectory(Directory directory) async {
  try {
    await directory.create(recursive: true);
    final probe =
        File('${directory.path}${Platform.pathSeparator}.cutter_probe');
    await probe.writeAsString('ok');
    await probe.delete();
    return true;
  } on Object {
    return false;
  }
}
