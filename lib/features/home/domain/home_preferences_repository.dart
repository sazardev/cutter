import 'package:cutter/features/home/domain/home_preferences.dart';

/// Where the home list preferences live, owned by the domain and implemented
/// at the edge.
abstract interface class HomePreferencesRepository {
  /// The saved preferences, or the defaults.
  Future<HomePreferences> load();

  /// Saves [preferences].
  Future<void> save(HomePreferences preferences);
}
