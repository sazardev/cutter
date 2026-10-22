import 'package:cutter/core/settings/settings_store.dart';
import 'package:uuid/uuid.dart';

/// Where the crash-report identifier is kept.
const String installIdKey = 'telemetry.install_id';

/// The identifier reports are tied to, created on first launch.
///
/// It is a random UUID, not a name or an account: it matches the reports of
/// one install across launches and nothing else.
Future<String> loadInstallId(SettingsStore store) async {
  final existing = (await store.read(installIdKey))?.trim();
  if (existing != null && existing.isNotEmpty) return existing;
  final id = const Uuid().v4();
  await store.write(installIdKey, id);
  return id;
}
