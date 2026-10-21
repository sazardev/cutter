import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/presentation/clip_tools.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/playback_controller.dart';
import 'package:cutter/features/editor/presentation/studio/clip_studio_page.dart';
import 'package:cutter/features/editor/presentation/tools/editor_tool.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a tap on a clip shows: a short pill with Edit, Duplicate, Split and
/// Delete, and More for the full options. Nothing else, so it stays out of
/// the way; a double tap on the clip opens the same full options.
class ClipQuickBar extends ConsumerWidget {
  /// Creates the bar; [actions] gives it Split.
  const ClipQuickBar({required this.actions, super.key});

  /// What the buttons do.
  final EditorActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final clip = ref.watch(editorControllerProvider).valueOrNull?.selectedClip;
    final controller = ref.read(editorControllerProvider.notifier);
    final playhead =
        ref.watch(playbackControllerProvider.select((p) => p.positionMs));
    if (clip == null) return const SizedBox.shrink();
    Widget button(
      IconData icon,
      String label,
      VoidCallback? onPressed, {
      Color? color,
    }) {
      return IconButton(
        tooltip: label,
        icon: Icon(icon, color: onPressed == null ? null : color),
        onPressed: onPressed == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onPressed();
              },
      );
    }

    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 3,
      borderRadius: BorderRadius.circular(AppRadii.large),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            button(
              Icons.edit_outlined,
              l10n.editClipAction,
              () => openClipStudio(context, clip.id),
            ),
            button(
              Icons.copy_outlined,
              l10n.duplicateAction,
              controller.duplicateSelected,
            ),
            button(
              Icons.content_cut,
              l10n.splitAction,
              controller.canSplitAt(playhead) ? actions.onSplit : null,
            ),
            button(
              Icons.delete_outline,
              l10n.deleteAction,
              controller.deleteSelected,
              color: scheme.error,
            ),
            SizedBox(
              height: 24,
              child: VerticalDivider(width: 12, color: scheme.outlineVariant),
            ),
            button(
              Icons.more_horiz,
              l10n.moreActions,
              () => ref.read(clipDetailsProvider.notifier).state = clip.id,
            ),
          ],
        ),
      ),
    );
  }
}
