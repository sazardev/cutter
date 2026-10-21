import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/settings/domain/changelog.dart';
import 'package:cutter/features/settings/presentation/app_info_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double _contentMaxWidth = 720;

/// The release notes: one card per version with its groups of changes.
class ChangelogPage extends ConsumerWidget {
  /// Creates the page.
  const ChangelogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final releases = ref.watch(changelogProvider);
    final margin = marginFor(windowClassOf(MediaQuery.sizeOf(context).width));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAboutChangelog)),
      body: SafeArea(
        child: releases.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(child: Text(l10n.changelogLoadError)),
          data: (list) => list.isEmpty
              ? Center(child: Text(l10n.changelogEmpty))
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: _contentMaxWidth),
                    child: ListView.separated(
                      padding: EdgeInsets.all(margin),
                      itemCount: list.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: AppSpacing.lg),
                      itemBuilder: (context, index) =>
                          _ReleaseCard(release: list[index]),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({required this.release});

  final ChangelogRelease release;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(release.version, style: theme.textTheme.headlineSmall),
                if (release.date.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    release.date,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            for (final group in release.groups) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                group.title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final item in group.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(
                          top: AppSpacing.xs,
                          right: AppSpacing.md,
                        ),
                        child: Icon(Icons.circle, size: AppSpacing.sm),
                      ),
                      Expanded(
                        child: Text(item, style: theme.textTheme.bodyMedium),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
