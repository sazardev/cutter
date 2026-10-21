import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/backup/data/backup_reader.dart';
import 'package:cutter/features/backup/data/backup_writer.dart';
import 'package:cutter/features/backup/domain/backup_format.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/tools/export_panel.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks for a backup file; null when cancelled. Tests replace it.
final backupPickerProvider = Provider<Future<String?> Function()>(
  (ref) => () async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [backupExtension],
    );
    return picked.firstOrNull?.path;
  },
);

String _failureText(AppLocalizations l10n, BackupFailure failure) =>
    switch (failure) {
      BackupFailure.notABackup => l10n.backupNotABackup,
      BackupFailure.newerVersion => l10n.backupNewerVersion,
      BackupFailure.damaged => l10n.backupDamaged,
      BackupFailure.storageFull => l10n.backupStorageFull,
      BackupFailure.io => l10n.backupIoError,
    };

Future<void> _message(
  BuildContext context,
  String title,
  List<String> lines,
) {
  final l10n = AppLocalizations.of(context)!;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(line),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.importReportClose),
        ),
      ],
    ),
  );
}

/// Shows a spinner over everything while [work] runs.
Future<T> _whileWorking<T>(BuildContext context, Future<T> Function() work) {
  final l10n = AppLocalizations.of(context)!;
  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: Text(l10n.backupWorking)),
          ],
        ),
      ),
    ),
  );
  return work().whenComplete(navigator.pop);
}

/// Writes a backup of project [projectId] into the export folder and says
/// where it went and what it holds.
Future<void> backUpProject(
  BuildContext context,
  WidgetRef ref,
  String projectId,
) async {
  final l10n = AppLocalizations.of(context)!;
  final project = await ref.read(projectRepositoryProvider).find(projectId);
  if (project == null || !context.mounted) return;
  try {
    final dir = await ref.read(exportDirectoryProvider.future);
    final safe = project.name.replaceAll(RegExp(r'[^\w\- ]'), '_');
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp('[^0-9]'), '')
        .substring(0, 14);
    final path = '${dir.path}/${safe}_$stamp.$backupExtension';
    if (!context.mounted) return;
    final result = await _whileWorking(
      context,
      () => writeBackup(project, path),
    );
    if (!context.mounted) return;
    await _message(context, l10n.backupSavedTitle, [
      l10n.backupSavedBody(result.mediaCount),
      if (result.missingCount > 0) l10n.backupSavedMissing(result.missingCount),
      l10n.backupSavedWhere(result.path),
    ]);
  } on BackupException catch (error) {
    if (context.mounted) {
      await _message(context, l10n.backupFailedTitle, [
        _failureText(l10n, error.failure),
      ]);
    }
  }
}

/// Opens a backup the user picks and adds its project to the projects.
/// Returns whether a project was added.
Future<bool> restoreFromBackup(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;
  final path = await ref.read(backupPickerProvider)();
  if (path == null || !context.mounted) return false;
  try {
    final library = await ref.read(mediaLibraryProvider.future);
    if (!context.mounted) return false;
    final project = await _whileWorking(context, () async {
      final restored = await readBackup(
        path,
        mediaRoot: library.root,
        ids: ref.read(idGeneratorProvider),
      );
      final named = restored.withName(l10n.backupRestoredName(restored.name));
      await ref.read(projectRepositoryProvider).save(named);
      return named;
    });
    ref.invalidate(projectSummariesProvider);
    if (context.mounted) {
      await _message(context, l10n.restoreDoneTitle, [
        l10n.restoreDoneBody(project.name),
      ]);
    }
    return true;
  } on BackupException catch (error) {
    if (context.mounted) {
      await _message(context, l10n.restoreFailedTitle, [
        _failureText(l10n, error.failure),
      ]);
    }
    return false;
  }
}
