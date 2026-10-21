import 'package:cutter/features/settings/domain/appearance_settings.dart';

/// Where the appearance preferences live, owned by the domain and
/// implemented at the edge.
abstract interface class AppearanceRepository {
  /// The saved preferences, or the defaults for anything not saved yet or
  /// unreadable.
  Future<AppearanceSettings> load();

  /// Saves [settings] so the next launch starts with them.
  Future<void> save(AppearanceSettings settings);
}
