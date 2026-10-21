import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/library/presentation/videos_section.dart';
import 'package:cutter/features/settings/presentation/settings_widgets.dart';
import 'package:cutter/features/storage/domain/storage_report.dart';
import 'package:cutter/features/storage/presentation/storage_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double _barHeight = 12;
const double _legendDot = 10;

/// What Cutter keeps on the device: the total with a bar of its parts, the
/// cache and the unused media with their cleaning, and the space each
/// project takes.
class StorageSection extends ConsumerStatefulWidget {
  /// Creates the section.
  const StorageSection({super.key});

  @override
  ConsumerState<StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends ConsumerState<StorageSection> {
  /// What the last cleaning freed, shown beside the row that did it.
  String? _cacheFreed;
  String? _unusedFreed;

  Future<void> _clearCache(AppLocalizations l10n) async {
    final freed = await clearAppCache(ref);
    if (mounted)
      setState(() => _cacheFreed = l10n.storageFreed(formatBytes(freed)));
  }

  Future<void> _cleanUnused(
    AppLocalizations l10n,
    StorageReport report,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.storageCleanTitle),
        content: Text(
          l10n.storageCleanBody(
            report.unusedPaths.length,
            formatBytes(report.unusedBytes),
          ),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.storageCleanUnused),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final freed = await deleteUnusedMedia(ref, report);
    if (mounted)
      setState(() => _unusedFreed = l10n.storageFreed(formatBytes(freed)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(storageReportProvider);
    final report = async.valueOrNull;
    if (report == null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: async.hasError
              ? TextButton.icon(
                  onPressed: () => ref.invalidate(storageReportProvider),
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.storageRefresh),
                )
              : const CircularProgressIndicator(),
        ),
      );
    }

    return Column(
      children: [
        _Overview(report: report),
        const SizedBox(height: AppSpacing.xl),
        SettingsGroup(
          children: [
            SettingsTile(
              icon: Icons.cleaning_services_outlined,
              title: l10n.storageCache,
              subtitle: _cacheFreed ??
                  '${formatBytes(report.cacheBytes)} · '
                      '${l10n.storageCacheHelp}',
              trailing: FilledButton.tonal(
                onPressed:
                    report.cacheBytes == 0 ? null : () => _clearCache(l10n),
                child: Text(l10n.storageClearCache),
              ),
            ),
            SettingsTile(
              icon: Icons.layers_clear_outlined,
              title: l10n.storageUnusedTitle,
              subtitle: _unusedFreed ??
                  '${formatBytes(report.unusedBytes)} · '
                      '${l10n.storageUnusedHelp(report.unusedPaths.length)}',
              trailing: FilledButton.tonal(
                onPressed: report.unusedPaths.isEmpty
                    ? null
                    : () => _cleanUnused(l10n, report),
                child: Text(l10n.storageCleanUnused),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        _ProjectsList(report: report),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => ref.invalidate(storageReportProvider),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.storageRefresh),
          ),
        ),
      ],
    );
  }
}

/// The total and a bar split into media, exported videos and cache.
class _Overview extends StatelessWidget {
  const _Overview({required this.report});

  final StorageReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final parts = [
      (l10n.storageMedia, report.mediaBytes, scheme.primary),
      (l10n.storageExports, report.exportBytes, scheme.tertiary),
      (l10n.storageCache, report.cacheBytes, scheme.outline),
    ];
    final total = report.totalBytes;
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.storageTotal(formatBytes(total)),
              style: theme.textTheme.headlineSmall?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ClipRRect(
              borderRadius: BorderRadius.circular(_barHeight / 2),
              child: SizedBox(
                height: _barHeight,
                child: total == 0
                    ? ColoredBox(color: scheme.surfaceContainerHighest)
                    : Row(
                        children: [
                          for (final (_, bytes, color) in parts)
                            if (bytes > 0)
                              Expanded(
                                flex: bytes,
                                child: ColoredBox(color: color),
                              ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.xs,
              children: [
                for (final (label, bytes, color) in parts)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: _legendDot,
                        height: _legendDot,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '$label ${formatBytes(bytes)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The projects with the space their media takes, the biggest first, each
/// with a bar relative to the biggest.
class _ProjectsList extends StatelessWidget {
  const _ProjectsList({required this.report});

  final StorageReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final biggest = report.projects.isEmpty ? 0 : report.projects.first.bytes;
    return SettingsGroup(
      title: l10n.storageByProject,
      children: [
        if (report.projects.isEmpty)
          SettingsTile(title: l10n.storageProjectsNone)
        else
          for (final project in report.projects)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          project.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text(
                        formatBytes(project.bytes),
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(_barHeight / 2),
                    child: LinearProgressIndicator(
                      minHeight: _barHeight / 2,
                      value: biggest == 0 ? 0 : project.bytes / biggest,
                    ),
                  ),
                  if (project.trashed || project.sharedBytes > 0) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      [
                        if (project.trashed) l10n.storageProjectTrash,
                        if (project.sharedBytes > 0)
                          l10n.storageProjectShared(
                            formatBytes(project.sharedBytes),
                          ),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
      ],
    );
  }
}
