import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/domain/import_media.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/presentation/import_flow.dart';
import 'package:cutter/features/editor/presentation/tools/editor_tool.dart';
import 'package:cutter/features/editor/presentation/tools/text_panel.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks which kind of layer to add, then does it: media kinds open the
/// picker for that kind and put the files on a new layer in front; Text adds
/// a text at the playhead and opens the text tool to type over it.
Future<void> showAddLayerMenu(BuildContext context, WidgetRef ref) async {
  final choice = await showModalBottomSheet<MediaKind>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => const _AddLayerSheet(),
  );
  if (choice == null || !context.mounted) return;
  if (choice == MediaKind.text) {
    final id = await addTextAtPlayhead(context, ref);
    if (id != null) {
      ref.read(activeToolProvider.notifier).state = EditorTool.text;
    }
    return;
  }
  await pickAndImport(
    context,
    ref,
    placement: ImportPlacement.overlay,
    filter: choice,
  );
}

class _AddLayerSheet extends StatelessWidget {
  const _AddLayerSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final options = [
      (
        MediaKind.video,
        Icons.movie_outlined,
        l10n.layerKindVideo,
        l10n.addLayerVideoHint
      ),
      (
        MediaKind.image,
        Icons.image_outlined,
        l10n.layerKindImage,
        l10n.addLayerImageHint
      ),
      (
        MediaKind.audio,
        Icons.music_note_outlined,
        l10n.layerKindAudio,
        l10n.addLayerAudioHint
      ),
      (
        MediaKind.text,
        Icons.text_fields,
        l10n.layerKindText,
        l10n.addLayerTextHint
      ),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.sm,
                bottom: AppSpacing.sm,
              ),
              child:
                  Text(l10n.addLayerTitle, style: theme.textTheme.titleMedium),
            ),
            for (final (kind, icon, title, hint) in options)
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  foregroundColor: theme.colorScheme.onSecondaryContainer,
                  child: Icon(icon),
                ),
                title: Text(title),
                subtitle: Text(hint),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pop(kind),
              ),
          ],
        ),
      ),
    );
  }
}
