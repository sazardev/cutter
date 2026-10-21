import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/settings/domain/share_preferences.dart';
import 'package:cutter/features/settings/presentation/settings_widgets.dart';
import 'package:cutter/features/settings/presentation/share_platform_labels.dart';
import 'package:cutter/features/settings/presentation/share_preferences_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Returns the preferences with one setting set to [on]; the share section
/// uses it for each of its switches.
typedef ShareToggleApply = SharePreferences Function(
  SharePreferences current, {
  required bool on,
});

/// What shows once a video is exported: the share options, which platform
/// shortcuts, the actions on the result, and whether the share sheet opens
/// by itself.
class ShareSection extends ConsumerWidget {
  /// Creates the section.
  const ShareSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final preferences = ref.watch(sharePreferencesProvider);
    final controller = ref.read(sharePreferencesProvider.notifier);

    Widget toggle({
      required IconData icon,
      required String title,
      required String subtitle,
      required bool value,
      required ShareToggleApply apply,
      bool enabled = true,
    }) {
      return SettingsTile(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: enabled
            ? () => controller.update((current) => apply(current, on: !value))
            : null,
        trailing: Switch(
          value: value,
          onChanged: enabled
              ? (v) => controller.update((current) => apply(current, on: v))
              : null,
        ),
      );
    }

    return Column(
      children: [
        SettingsGroup(
          children: [
            toggle(
              icon: Icons.ios_share,
              title: l10n.settingsShareShowTitle,
              subtitle: l10n.settingsShareShowHelp,
              value: preferences.showAfterExport,
              apply: (p, {required on}) => p.copyWith(showAfterExport: on),
            ),
            toggle(
              icon: Icons.open_in_new,
              title: l10n.settingsShareAutoTitle,
              subtitle: l10n.settingsShareAutoHelp,
              value: preferences.openSheetAutomatically,
              enabled: preferences.showAfterExport,
              apply: (p, {required on}) =>
                  p.copyWith(openSheetAutomatically: on),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        SettingsGroup(
          title: l10n.settingsSharePlatformsTitle,
          children: [
            for (final platform in SharePlatform.values)
              SettingsTile(
                icon: sharePlatformIcon(platform),
                title: sharePlatformLabel(l10n, platform),
                onTap: preferences.showAfterExport
                    ? () => controller.setPlatform(
                          platform,
                          shown: !preferences.platforms.contains(platform),
                        )
                    : null,
                trailing: Switch(
                  value: preferences.platforms.contains(platform),
                  onChanged: preferences.showAfterExport
                      ? (v) => controller.setPlatform(platform, shown: v)
                      : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        SettingsGroup(
          title: l10n.settingsShareActionsTitle,
          children: [
            toggle(
              icon: Icons.play_circle_outline,
              title: l10n.exportWatchAction,
              subtitle: l10n.settingsShareWatchHelp,
              value: preferences.showWatch,
              apply: (p, {required on}) => p.copyWith(showWatch: on),
            ),
            toggle(
              icon: Icons.folder_open_outlined,
              title: l10n.exportOpenFolderAction,
              subtitle: l10n.settingsShareFolderHelp,
              value: preferences.showOpenFolder,
              apply: (p, {required on}) => p.copyWith(showOpenFolder: on),
            ),
            toggle(
              icon: Icons.copy,
              title: l10n.copyPathAction,
              subtitle: l10n.settingsShareCopyHelp,
              value: preferences.showCopyPath,
              apply: (p, {required on}) => p.copyWith(showCopyPath: on),
            ),
          ],
        ),
      ],
    );
  }
}
