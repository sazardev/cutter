import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/domain/import_limits.dart';
import 'package:cutter/features/editor/presentation/editor_controller.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Tells the user what an import left out and why, and what to know about
/// files that came in anyway. Shown only when there is something to tell.
Future<void> showImportReport(BuildContext context, ImportOutcome outcome) {
  if (!outcome.hasReport) return Future.value();
  return showDialog<void>(
    context: context,
    builder: (context) => _ImportReportDialog(outcome: outcome),
  );
}

String _name(String path) => path.split(RegExp(r'[\\/]')).last;

class _ImportReportDialog extends StatelessWidget {
  const _ImportReportDialog({required this.outcome});

  final ImportOutcome outcome;

  String _issue(AppLocalizations l10n, ImportIssueKind kind) => switch (kind) {
        ImportIssueKind.unreadable => l10n.importIssueUnreadable,
        ImportIssueKind.tooShort => l10n.importIssueTooShort,
        ImportIssueKind.storageFull => l10n.importIssueStorageFull,
        ImportIssueKind.copyFailed => l10n.importIssueCopyFailed,
      };

  String _notice(AppLocalizations l10n, ImportNoticeKind kind) =>
      switch (kind) {
        ImportNoticeKind.highResolution => l10n.importNoticeHighResolution,
        ImportNoticeKind.longDuration => l10n.importNoticeLongDuration,
        ImportNoticeKind.largeFile => l10n.importNoticeLargeFile,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    Widget entry(String path, String reason) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_name(path), style: theme.textTheme.titleSmall),
              Text(
                reason,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
    return AlertDialog(
      title: Text(l10n.importReportTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.importReportDone(outcome.imported)),
            if (outcome.issues.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.importReportSkipped,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final issue in outcome.issues)
                entry(issue.path, _issue(l10n, issue.kind)),
            ],
            if (outcome.notices.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.importReportAttention,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final notice in outcome.notices)
                entry(notice.path, _notice(l10n, notice.kind)),
            ],
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
    );
  }
}
