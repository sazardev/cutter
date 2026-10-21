import 'package:cutter/core/settings/settings_store.dart';
import 'package:cutter/features/settings/domain/share_preferences.dart';

const _showKey = 'share.show_after_export';
const _autoKey = 'share.open_sheet_automatically';
const _platformsKey = 'share.platforms';
const _watchKey = 'share.show_watch';
const _folderKey = 'share.show_open_folder';
const _copyKey = 'share.show_copy_path';

/// Stores the share preferences as `app_settings` rows; the platforms are a
/// comma separated list of their names (empty when none is shown).
class DriftSharePreferencesRepository {
  /// Creates a repository over [_store].
  DriftSharePreferencesRepository(this._store);

  final SettingsStore _store;

  /// The saved preferences, or the defaults.
  Future<SharePreferences> load() async {
    final values = await _store.readPrefixed('share.');
    final platforms = values[_platformsKey];
    return SharePreferences(
      showAfterExport: values[_showKey] != 'false',
      openSheetAutomatically: values[_autoKey] == 'true',
      platforms: platforms == null
          ? SharePreferences.defaultPlatforms
          : {
              for (final name in platforms.split(','))
                for (final platform in SharePlatform.values)
                  if (platform.name == name) platform,
            },
      showWatch: values[_watchKey] != 'false',
      showOpenFolder: values[_folderKey] != 'false',
      showCopyPath: values[_copyKey] != 'false',
    );
  }

  /// Saves [preferences].
  Future<void> save(SharePreferences preferences) {
    return _store.writeAll({
      _showKey: preferences.showAfterExport.toString(),
      _autoKey: preferences.openSheetAutomatically.toString(),
      _platformsKey: [for (final p in preferences.platforms) p.name].join(','),
      _watchKey: preferences.showWatch.toString(),
      _folderKey: preferences.showOpenFolder.toString(),
      _copyKey: preferences.showCopyPath.toString(),
    });
  }
}
