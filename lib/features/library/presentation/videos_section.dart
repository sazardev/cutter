import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/domain/export_record.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/time_format.dart';
import 'package:cutter/features/library/presentation/library_previews.dart';
import 'package:cutter/features/library/presentation/video_viewer_page.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double _cardWidth = 156;
const double _posterHeight = 120;

/// The size of [bytes] for people: KB, MB or GB with one decimal.
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

/// "Your videos" on the home screen: the rendered videos, newest first, as
/// a row of posters. Nothing shows until there is one.
class VideosSection extends ConsumerWidget {
  /// Creates the section.
  const VideosSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final records = ref.watch(exportRecordsProvider).valueOrNull ?? const [];
    if (records.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Text(l10n.libraryTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.librarySummary(
            records.length,
            formatBytes(records.fold(0, (sum, r) => sum + r.sizeBytes)),
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: _posterHeight + 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: records.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, i) => _VideoCard(record: records[i]),
          ),
        ),
      ],
    );
  }
}

class _VideoCard extends ConsumerWidget {
  const _VideoCard({required this.record});

  final ExportRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final poster = ref.watch(videoPosterProvider(record.path)).valueOrNull;
    return SizedBox(
      width: _cardWidth,
      child: Semantics(
        button: true,
        label: l10n.openVideoLabel(record.projectName),
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.medium),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => VideoViewerPage(record: record),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.medium),
                child: Container(
                  height: _posterHeight,
                  width: _cardWidth,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (poster != null)
                        RawImage(image: poster, fit: BoxFit.cover),
                      Positioned(
                        right: AppSpacing.xs,
                        bottom: AppSpacing.xs,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.scrim.withValues(
                              alpha: 0.6,
                            ),
                            borderRadius:
                                BorderRadius.circular(AppRadii.small / 2),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                            ),
                            child: Text(
                              formatTimecode(record.durationMs),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onInverseSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                record.projectName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge,
              ),
              Text(
                '${record.width}×${record.height} · '
                '${formatBytes(record.sizeBytes)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
