import 'dart:io';

import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/share_video.dart';
import 'package:cutter/features/library/presentation/video_viewer_page.dart';
import 'package:cutter/features/settings/presentation/share_platform_labels.dart';
import 'package:cutter/features/settings/presentation/share_preferences_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What can be done with a finished video: share it (the system share sheet,
/// with a shortcut per platform the user chose), watch it, show its folder
/// and copy its path. Each part follows the preferences in Settings.
class ShareBlock extends ConsumerWidget {
  /// Creates the block for the video at [path], called [title].
  const ShareBlock({required this.path, required this.title, super.key});

  /// The file.
  final String path;

  /// The name offered to the apps it is shared with.
  final String title;

  Future<void> _watch(BuildContext context, WidgetRef ref) async {
    final records = await ref.read(exportRecordsProvider.future);
    final matching = records.where((r) => r.path == path);
    if (matching.isEmpty || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoViewerPage(record: matching.first),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final preferences = ref.watch(sharePreferencesProvider);
    final canShare = ref.watch(shareSupportedProvider);
    final canOpenFolder = ref.watch(folderOpeningSupportedProvider);
    final sharer = ref.read(videoSharerProvider);
    final showShare = preferences.showAfterExport && canShare;
    final actions = <Widget>[
      if (preferences.showWatch)
        TextButton.icon(
          onPressed: () => _watch(context, ref),
          icon: const Icon(Icons.play_circle_outline),
          label: Text(l10n.exportWatchAction),
        ),
      if (preferences.showOpenFolder && canOpenFolder)
        TextButton.icon(
          onPressed: () =>
              ref.read(folderOpenerProvider)(File(path).parent.path),
          icon: const Icon(Icons.folder_open_outlined),
          label: Text(l10n.exportOpenFolderAction),
        ),
      if (preferences.showCopyPath)
        TextButton.icon(
          onPressed: () => Clipboard.setData(ClipboardData(text: path)),
          icon: const Icon(Icons.copy),
          label: Text(l10n.copyPathAction),
        ),
    ];
    if (!showShare && actions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showShare) ...[
          FilledButton.icon(
            onPressed: () => sharer(path, title),
            icon: const Icon(Icons.ios_share),
            label: Text(l10n.shareVideoAction),
          ),
          if (preferences.platforms.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.sharePublishTo,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final platform
                    in preferences.platforms.toList()
                      ..sort((a, b) => a.index.compareTo(b.index)))
                  Tooltip(
                    message: l10n.sharePlatformHint(
                      sharePlatformLabel(l10n, platform),
                    ),
                    child: ActionChip(
                      avatar: Icon(sharePlatformIcon(platform), size: 18),
                      label: Text(sharePlatformLabel(l10n, platform)),
                      onPressed: () => sharer(path, title),
                    ),
                  ),
              ],
            ),
          ],
        ],
        if (actions.isNotEmpty) ...[
          if (showShare) const SizedBox(height: AppSpacing.xs),
          Wrap(spacing: AppSpacing.xs, children: actions),
        ],
      ],
    );
  }
}
