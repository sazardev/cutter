import 'package:cutter/core/settings/settings_store.dart';
import 'package:cutter/features/settings/domain/export_preferences.dart';
import 'package:cutter/features/settings/domain/export_preferences_repository.dart';

const _directoryKey = 'export.directory';
const _galleryKey = 'export.save_to_gallery';

/// Stores the export preferences as `app_settings` rows. A missing folder is
/// stored as an empty text.
class DriftExportPreferencesRepository implements ExportPreferencesRepository {
  /// Creates a repository over [_store].
  DriftExportPreferencesRepository(this._store);

  final SettingsStore _store;

  @override
  Future<ExportPreferences> load() async {
    final values = await _store.readPrefixed('export.');
    final directory = values[_directoryKey];
    return ExportPreferences(
      directory: directory == null || directory.isEmpty ? null : directory,
      saveToGallery: values[_galleryKey] != 'false',
    );
  }

  @override
  Future<void> save(ExportPreferences preferences) {
    return _store.writeAll({
      _directoryKey: preferences.directory ?? '',
      _galleryKey: preferences.saveToGallery.toString(),
    });
  }
}
