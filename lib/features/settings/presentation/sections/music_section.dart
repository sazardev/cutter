import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/library/presentation/videos_section.dart';
import 'package:cutter/features/music/domain/music_pack.dart';
import 'package:cutter/features/music/presentation/genre_icons.dart';
import 'package:cutter/features/music/presentation/music_library_controller.dart';
import 'package:cutter/features/music/presentation/music_library_page.dart';
import 'package:cutter/features/settings/presentation/settings_widgets.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The music packs on the device: what they take, and removing them.
class MusicSection extends ConsumerWidget {
  /// Creates the section.
  const MusicSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final state = ref.watch(musicLibraryProvider).valueOrNull;
    if (state == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final controller = ref.read(musicLibraryProvider.notifier);
    final installed = state.installed.values.toList()
      ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    final language = Localizations.localeOf(context).languageCode;

    Future<void> confirm({
      required String title,
      required String body,
      required Future<void> Function() onConfirm,
    }) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancelAction),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.deleteAction),
            ),
          ],
        ),
      );
      if (ok ?? false) await onConfirm();
    }

    return Column(
      children: [
        SettingsGroup(
          children: [
            SettingsTile(
              icon: Icons.storage_outlined,
              title: l10n.settingsMusicUsed,
              subtitle: l10n.settingsMusicUsedValue(
                formatBytes(state.usedBytes),
                installed.length,
              ),
            ),
            SettingsTile(
              icon: Icons.library_music_outlined,
              title: l10n.settingsMusicBrowse,
              subtitle: l10n.settingsMusicBrowseHelp,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MusicLibraryPage(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        if (installed.isEmpty)
          SettingsGroup(
            children: [
              SettingsTile(
                icon: Icons.music_off_outlined,
                title: l10n.settingsMusicNone,
              ),
            ],
          )
        else ...[
          SettingsGroup(
            title: l10n.settingsMusicPacksTitle,
            children: [
              for (final pack in installed)
                _PackRow(
                  pack: pack,
                  name: pack.pack.nameIn(language),
                  onRemove: () => confirm(
                    title: l10n.settingsMusicRemoveTitle(
                      pack.pack.nameIn(language),
                    ),
                    body: l10n.settingsMusicRemoveBody(
                      formatBytes(pack.sizeBytes),
                    ),
                    onConfirm: () => controller.remove(pack.pack.id),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          SettingsGroup(
            children: [
              SettingsTile(
                icon: Icons.delete_sweep_outlined,
                title: l10n.settingsMusicRemoveAll,
                subtitle: l10n.settingsMusicRemoveAllHelp(
                  formatBytes(state.usedBytes),
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.error,
                ),
                onTap: () => confirm(
                  title: l10n.settingsMusicRemoveAll,
                  body: l10n.settingsMusicRemoveAllHelp(
                    formatBytes(state.usedBytes),
                  ),
                  onConfirm: controller.removeAll,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PackRow extends StatelessWidget {
  const _PackRow({
    required this.pack,
    required this.name,
    required this.onRemove,
  });

  final InstalledPack pack;
  final String name;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SettingsTile(
      icon: genreIcon(pack.pack.genre),
      title: name,
      subtitle: l10n.settingsMusicPackSummary(
        pack.tracks.length,
        formatBytes(pack.sizeBytes),
      ),
      trailing: IconButton(
        tooltip: l10n.musicPackRemove,
        onPressed: onRemove,
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }
}
