import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/settings/presentation/app_info_providers.dart';
import 'package:cutter/features/settings/presentation/changelog_page.dart';
import 'package:cutter/features/settings/presentation/settings_widgets.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The version, the changelog and the open-source licenses.
class AboutSection extends ConsumerWidget {
  /// Creates the section.
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final version = ref.watch(appVersionProvider).valueOrNull;

    return Column(
      children: [
        Card(
          margin: EdgeInsets.zero,
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Row(
              children: [
                Icon(
                  Icons.movie_edit,
                  size: AppSpacing.giant,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cutter',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l10n.settingsAboutTagline,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        SettingsGroup(
          children: [
            SettingsTile(
              icon: Icons.sell_outlined,
              title: l10n.settingsAboutVersion,
              subtitle: version == null
                  ? null
                  : l10n.settingsAboutVersionValue(
                      version.version,
                      version.build,
                    ),
            ),
            SettingsTile(
              icon: Icons.history,
              title: l10n.settingsAboutChangelog,
              subtitle: l10n.settingsAboutChangelogHelp,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const ChangelogPage(),
                ),
              ),
            ),
            SettingsTile(
              icon: Icons.description_outlined,
              title: l10n.settingsAboutLicenses,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Cutter',
                applicationVersion: version?.version,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
