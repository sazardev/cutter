import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/editor/domain/animation_preset.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/presentation/animation_preset_providers.dart';
import 'package:cutter/features/editor/presentation/clip_tools.dart'
    show animationLabel;
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/tools/panel_kit.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether a preset goes to every clip of the layer instead of the selected
/// clip only.
final _wholeLayerProvider = StateProvider.autoDispose<bool>((ref) => false);

/// The preset that removes both animations of a clip.
const _noAnimation = AnimationPreset(
  id: 'none',
  animIn: null,
  animInMs: 0,
  animOut: null,
  animOutMs: 0,
);

/// Whether [clip] has exactly the animation of [preset].
bool _matches(Clip clip, AnimationPreset preset) =>
    clip.animIn == preset.animIn &&
    clip.animOut == preset.animOut &&
    (preset.animIn == null || clip.animInMs == preset.animInMs) &&
    (preset.animOut == null || clip.animOutMs == preset.animOutMs);

String _builtInName(AppLocalizations l10n, String id) => switch (id) {
      'gentle' => l10n.animationPresetGentle,
      'quick_fade' => l10n.animationPresetQuickFade,
      'cinematic' => l10n.animationPresetCinematic,
      'slide_through' => l10n.animationPresetSlideThrough,
      'slide_up_down' => l10n.animationPresetSlideUpDown,
      'zoom' => l10n.animationPresetZoom,
      'pop' => l10n.animationPresetPop,
      'spin' => l10n.animationPresetSpin,
      _ => id,
    };

/// "Fade 0.5 s", or the word for none.
String _step(AppLocalizations l10n, String? id, int ms) => id == null
    ? l10n.animationNone
    : l10n.animationPresetStep(
        animationLabel(l10n, id),
        (ms / 1000).toStringAsFixed(1),
      );

/// Ready-made entrance and exit animations, and the ones the user saved.
/// One tap sets both sides of the selected clip (or of its whole layer);
/// the sliders of the animation panel then adjust the result.
class AnimationPresets extends ConsumerWidget {
  /// Creates the section.
  const AnimationPresets({super.key});

  Future<void> _apply(
    WidgetRef ref,
    AnimationPreset preset,
  ) =>
      ref.read(editorControllerProvider.notifier).applyAnimationPreset(
            preset,
            wholeLayer: ref.read(_wholeLayerProvider),
          );

  Future<void> _save(BuildContext context, WidgetRef ref, Clip clip) async {
    final l10n = AppLocalizations.of(context)!;
    if (clip.animIn == null && clip.animOut == null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l10n.animationPresetNeedsAnimation),
          actions: [
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.importReportClose),
            ),
          ],
        ),
      );
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _NameDialog(),
    );
    if (name == null) return;
    final result = await ref
        .read(saveAnimationPresetProvider)
        .call(clip: clip, name: name);
    if (result is Ok<AnimationPreset>)
      ref.invalidate(userAnimationPresetsProvider);
  }

  Future<void> _delete(WidgetRef ref, AnimationPreset preset) async {
    await ref.read(animationPresetRepositoryProvider).delete(preset.id);
    ref.invalidate(userAnimationPresetsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final clip = ref.watch(editorControllerProvider).valueOrNull?.selectedClip;
    // Sound has no picture to animate and a title has its own animation.
    if (clip == null || clip.kind == MediaKind.audio || clip.text != null) {
      return const SizedBox.shrink();
    }
    final mine = ref.watch(userAnimationPresetsProvider).valueOrNull ??
        const <AnimationPreset>[];
    final whole = ref.watch(_wholeLayerProvider);

    Widget option(AnimationPreset preset, {Widget? action}) {
      final name = preset.name ?? _builtInName(l10n, preset.id);
      final tile = OptionTile(
        icon: preset.isEmpty ? Icons.block : Icons.auto_awesome_motion,
        title: preset.id == 'none' ? l10n.animationPresetNone : name,
        subtitle: preset.isEmpty
            ? null
            : l10n.animationPresetSummaryLine(
                _step(l10n, preset.animIn, preset.animInMs),
                _step(l10n, preset.animOut, preset.animOutMs),
              ),
        selected: _matches(clip, preset),
        onTap: () => _apply(ref, preset),
      );
      if (action == null) return tile;
      return Row(
        children: [
          Expanded(child: tile),
          action,
        ],
      );
    }

    return ToolSection(
      icon: Icons.auto_awesome_motion,
      title: l10n.animationPresetsTitle,
      summary: l10n.animationPresetsSummary,
      children: [
        option(_noAnimation),
        for (final preset in builtInAnimationPresets) option(preset),
        if (mine.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.xs,
            ),
            child: Text(
              l10n.animationPresetYours,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          for (final preset in mine)
            option(
              preset,
              action: IconButton(
                tooltip: l10n.animationPresetDelete,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(ref, preset),
              ),
            ),
        ],
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          title: Text(l10n.animationPresetWholeLayer),
          value: whole,
          onChanged: (value) =>
              ref.read(_wholeLayerProvider.notifier).state = value,
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => _save(context, ref, clip),
            icon: const Icon(Icons.bookmark_add_outlined),
            label: Text(l10n.animationPresetSave),
          ),
        ),
      ],
    );
  }
}

/// Asks for the name of a new preset; pops it, or null when cancelled.
class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.animationPresetSave),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: maxPresetNameLength,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: l10n.animationPresetNameLabel,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.animationPresetSaveConfirm),
        ),
      ],
    );
  }
}
