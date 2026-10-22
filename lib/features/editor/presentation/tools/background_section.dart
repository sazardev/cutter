import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/tools/panel_kit.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cuts the subject of the selected picture out of its background. Shown
/// for image clips only; the engine works off the UI thread and the button
/// reads as busy until it is done.
class BackgroundSection extends ConsumerStatefulWidget {
  /// Creates the section.
  const BackgroundSection({super.key});

  @override
  ConsumerState<BackgroundSection> createState() => _BackgroundSectionState();
}

class _BackgroundSectionState extends ConsumerState<BackgroundSection> {
  bool _working = false;

  Future<void> _cut(String clipId) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failed = AppLocalizations.of(context)!.removeBackgroundFailed;
    setState(() => _working = true);
    final ok = await ref
        .read(editorControllerProvider.notifier)
        .removeBackground(clipId);
    if (!ok) messenger?.showSnackBar(SnackBar(content: Text(failed)));
    if (mounted) setState(() => _working = false);
  }

  @override
  Widget build(BuildContext context) {
    final clip = ref.watch(editorControllerProvider).valueOrNull?.selectedClip;
    if (clip == null || clip.kind != MediaKind.image || clip.text != null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return ToolSection(
      icon: Icons.content_cut,
      title: l10n.removeBackgroundTitle,
      children: [
        Text(
          l10n.removeBackgroundHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.tonalIcon(
          onPressed: _working ? null : () => _cut(clip.id),
          icon: _working
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_fix_high),
          label: Text(
            _working
                ? l10n.removeBackgroundWorking
                : l10n.removeBackgroundAction,
          ),
        ),
      ],
    );
  }
}
