import 'dart:io';

import 'package:cutter/features/editor/presentation/layout/editor_layout.dart';
import 'package:cutter/features/settings/presentation/export_preferences_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The settings key holding the folder where videos of project [projectId]
/// are saved; empty when the project uses the default folder.
String projectExportDirKey(String projectId) => 'project.$projectId.export_dir';

/// The folder chosen for the videos of a project, or null for the default
/// one (the folder set in Settings).
final projectExportDirProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, projectId) async {
  final value = await ref
      .watch(settingsStoreProvider)
      .read(projectExportDirKey(projectId));
  return value == null || value.isEmpty ? null : value;
});

/// The folder to write the videos of [projectId] to: its own folder when it
/// has one that can be written, else null (use the default).
Future<Directory?> projectExportDirectory(Ref ref, String projectId) async {
  final chosen = await ref.read(projectExportDirProvider(projectId).future);
  if (chosen == null) return null;
  final directory = Directory(chosen);
  return await isWritableDirectory(directory) ? directory : null;
}
