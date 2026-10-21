import 'dart:io';

import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/home/presentation/home_providers.dart';
import 'package:cutter/features/storage/data/project_media_index.dart';
import 'package:cutter/features/storage/data/storage_scanner.dart';
import 'package:cutter/features/storage/domain/storage_report.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// The app's own cache folder, the only one ever cleaned. (Not the system
/// temporary folder: on desktop that is shared with every other program.)
/// Tests replace it.
final cacheDirectoryProvider = FutureProvider<Directory>(
  (ref) => getApplicationCacheDirectory(),
);

/// What Cutter keeps on the device. Invalidate it after cleaning.
final storageReportProvider = FutureProvider.autoDispose<StorageReport>(
  (ref) async {
    final library = await ref.watch(mediaLibraryProvider.future);
    final cache = await ref.watch(cacheDirectoryProvider.future);
    final trashed = ref.read(homePreferencesProvider).trashedAtMs.keys.toSet();
    final projects = await readProjectMedia(
      ref.read(appDatabaseProvider),
      trashedIds: trashed,
    );
    final exports = await ref.watch(exportRecordsProvider.future);
    return scanStorage(
      mediaRoot: library.root,
      cacheDir: cache,
      projects: projects,
      exportBytes:
          exports.fold<int>(0, (sum, record) => sum + record.sizeBytes),
    );
  },
);

/// Clears old cache files and returns the bytes freed.
Future<int> clearAppCache(WidgetRef ref) async {
  final cache = await ref.read(cacheDirectoryProvider.future);
  final freed = clearCache(cache);
  ref.invalidate(storageReportProvider);
  return freed;
}

/// Deletes the media no project uses and returns the bytes freed. [report]
/// is the scan the user saw and confirmed.
Future<int> deleteUnusedMedia(WidgetRef ref, StorageReport report) async {
  final library = await ref.read(mediaLibraryProvider.future);
  final freed = deleteMediaFiles(library.root, report.unusedPaths);
  ref
    ..invalidate(storageReportProvider)
    ..invalidate(projectSummariesProvider);
  return freed;
}
