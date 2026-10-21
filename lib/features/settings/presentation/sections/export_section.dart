import 'dart:io';

import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/editor/presentation/tools/export_panel.dart';
import 'package:cutter/features/settings/presentation/export_preferences_providers.dart';
import 'package:cutter/features/settings/presentation/settings_widgets.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where finished videos are saved: the gallery switch and the folder.
class ExportSection extends ConsumerWidget {
  /// Creates the section.
  const ExportSection({super.key});

  bool get _hasGallery => Platform.isAndroid || Platform.isIOS;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final preferences = ref.watch(exportPreferencesProvider);
    final controller = ref.read(exportPreferencesProvider.notifier);
    final effective = ref.watch(exportDirectoryProvider).valueOrNull?.path;

    return Column(
      children: [
        if (_hasGallery) ...[
          SettingsGroup(
            children: [
              SettingsTile(
                icon: Icons.photo_library_outlined,
                title: l10n.settingsExportGalleryTitle,
                subtitle: l10n.settingsExportGalleryHelp,
                onTap: () => controller.update(
                  (current) =>
                      current.copyWith(saveToGallery: !current.saveToGallery),
                ),
                trailing: Switch(
                  value: preferences.saveToGallery,
                  onChanged: (value) => controller.update(
                    (current) => current.copyWith(saveToGallery: value),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        SettingsGroup(
          children: [
            SettingsBlock(
              title: l10n.settingsExportFolderTitle,
              help: l10n.settingsExportFolderHelp,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadii.small),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder_outlined,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            preferences.directory == null
                                ? l10n.settingsExportFolderDefault
                                : (effective ?? preferences.directory!),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (preferences.directory == null && effective != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        effective,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => _choose(context, ref),
                        icon: const Icon(Icons.drive_file_move_outline),
                        label: Text(l10n.settingsExportFolderChoose),
                      ),
                      if (preferences.directory != null)
                        TextButton(
                          onPressed: () => controller.update(
                            (current) => current.copyWith(clearDirectory: true),
                          ),
                          child: Text(l10n.settingsExportFolderUseDefault),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final path = await ref.read(directoryPickerProvider)();
    if (path == null) return;
    // A folder that cannot be written to is not taken.
    if (!await isWritableDirectory(Directory(path))) return;
    await ref
        .read(exportPreferencesProvider.notifier)
        .update((current) => current.copyWith(directory: path));
  }
}
