import 'package:cutter/features/settings/domain/changelog.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The installed version of the app.
class AppVersion {
  /// Creates a version.
  const AppVersion(this.version, this.build);

  /// The user-facing version, e.g. `0.1.0`.
  final String version;

  /// The build number, e.g. `1`.
  final String build;
}

/// The version and build of the running app. Tests replace it.
final appVersionProvider = FutureProvider<AppVersion>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return AppVersion(info.version, info.buildNumber);
});

/// The releases listed in the bundled `CHANGELOG.md`, newest first.
final changelogProvider = FutureProvider<List<ChangelogRelease>>((ref) async {
  return parseChangelog(await rootBundle.loadString('CHANGELOG.md'));
});
