import 'package:cutter/features/settings/domain/export_preferences.dart';

/// Where the export preferences live, owned by the domain and implemented at
/// the edge.
abstract interface class ExportPreferencesRepository {
  /// The saved preferences, or the defaults.
  Future<ExportPreferences> load();

  /// Saves [preferences].
  Future<void> save(ExportPreferences preferences);
}
