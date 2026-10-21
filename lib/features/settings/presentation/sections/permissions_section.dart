import 'dart:io';

import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/settings/presentation/permission_providers.dart';
import 'package:cutter/features/settings/presentation/settings_widgets.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The permissions Cutter uses and a shortcut to the system settings.
class PermissionsSection extends ConsumerWidget {
  /// Creates the section.
  const PermissionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    if (!Platform.isAndroid && !Platform.isIOS) {
      return SettingsGroup(
        children: [
          SettingsTile(
            icon: Icons.verified_user_outlined,
            title: l10n.settingsPermissionsNone,
          ),
        ],
      );
    }
    final granted = ref.watch(galleryAccessProvider).valueOrNull;

    return Column(
      children: [
        SettingsGroup(
          children: [
            SettingsTile(
              icon: Icons.photo_library_outlined,
              title: l10n.settingsPermissionsGalleryTitle,
              subtitle: l10n.settingsPermissionsGalleryHelp,
              trailing: granted == null
                  ? null
                  : granted
                      ? _StatusChip(label: l10n.settingsPermissionAllowed)
                      : FilledButton.tonal(
                          onPressed: () async {
                            await ref.read(requestGalleryAccessProvider)();
                            ref.invalidate(galleryAccessProvider);
                          },
                          child: Text(l10n.settingsPermissionAllow),
                        ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        SettingsGroup(
          children: [
            SettingsTile(
              icon: Icons.settings_applications_outlined,
              title: l10n.settingsPermissionsOpenSettings,
              subtitle: l10n.settingsPermissionsOpenSettingsHelp,
              trailing: const Icon(Icons.open_in_new),
              onTap: () async {
                await ref.read(openSystemSettingsProvider)();
                // The user may have changed a permission over there.
                ref.invalidate(galleryAccessProvider);
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(Icons.check, size: 18, color: scheme.onSecondaryContainer),
      label: Text(label),
      backgroundColor: scheme.secondaryContainer,
      side: BorderSide.none,
    );
  }
}
