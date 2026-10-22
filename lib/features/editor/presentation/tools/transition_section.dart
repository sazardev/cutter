import 'package:cutter/features/editor/domain/clip_transition.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/tools/panel_kit.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const int _defaultTransitionMs = 600;

String _name(AppLocalizations l10n, TransitionKind kind) => switch (kind) {
      TransitionKind.dip => l10n.transitionDip,
      TransitionKind.pushLeft => l10n.transitionPushLeft,
      TransitionKind.pushRight => l10n.transitionPushRight,
      TransitionKind.pushUp => l10n.transitionPushUp,
      TransitionKind.pushDown => l10n.transitionPushDown,
      TransitionKind.zoomThrough => l10n.transitionZoomThrough,
      TransitionKind.spin => l10n.transitionSpin,
      TransitionKind.pop => l10n.transitionPop,
    };

IconData _icon(TransitionKind kind) => switch (kind) {
      TransitionKind.dip => Icons.blur_on,
      TransitionKind.pushLeft => Icons.arrow_back,
      TransitionKind.pushRight => Icons.arrow_forward,
      TransitionKind.pushUp => Icons.arrow_upward,
      TransitionKind.pushDown => Icons.arrow_downward,
      TransitionKind.zoomThrough => Icons.zoom_out_map,
      TransitionKind.spin => Icons.rotate_right,
      TransitionKind.pop => Icons.bubble_chart_outlined,
    };

/// Whether the sound fades with the next transition applied.
final _fadeSoundProvider = StateProvider.autoDispose<bool>((ref) => true);

/// How the selected clip follows the clip right before it on its layer: a
/// transition (a fade, a push, a zoom...) of a chosen length, applied to
/// both clips of the join at once. It shows only when there is a clip before
/// this one.
class TransitionSection extends ConsumerStatefulWidget {
  /// Creates the section.
  const TransitionSection({super.key});

  @override
  ConsumerState<TransitionSection> createState() => _TransitionSectionState();
}

class _TransitionSectionState extends ConsumerState<TransitionSection> {
  /// The length being dragged, before it is saved.
  int? _dragged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final editor = ref.watch(editorControllerProvider).valueOrNull;
    final clip = editor?.selectedClip;
    if (editor == null || clip == null || clip.text != null) {
      return const SizedBox.shrink();
    }
    final layer = editor.project.layerOfClip(clip.id);
    final first = layer == null ? null : previousNeighbour(layer, clip);
    final controller = ref.read(editorControllerProvider.notifier);

    if (first == null) {
      return ToolSection(
        icon: Icons.swap_horiz,
        title: l10n.transitionTitle,
        summary: l10n.transitionNeedsNeighbour,
        children: [PanelHint(l10n.transitionNeedsNeighbour)],
      );
    }

    final current = transitionBetween(first, clip);
    final stored = clip.animInMs > 0 ? clip.animInMs : _defaultTransitionMs;
    final ms = (_dragged ?? stored).clamp(minTransitionMs, maxTransitionMs);
    final fadeSound = ref.watch(_fadeSoundProvider);

    Future<void> apply(TransitionKind kind, [int? length]) =>
        controller.applyTransition(
          kind,
          length ?? ms,
          fadeSound: fadeSound,
        );

    return ToolSection(
      icon: Icons.swap_horiz,
      title: l10n.transitionTitle,
      summary: current == null ? l10n.transitionNone : _name(l10n, current),
      children: [
        OptionTile(
          icon: Icons.block,
          title: l10n.transitionNone,
          selected: current == null,
          onTap: controller.removeTransition,
        ),
        for (final kind in TransitionKind.values)
          OptionTile(
            icon: _icon(kind),
            title: _name(l10n, kind),
            selected: current == kind,
            onTap: () => apply(kind),
          ),
        SliderTile(
          title: l10n.transitionDuration((ms / 1000).toStringAsFixed(1)),
          value: ms.toDouble(),
          min: minTransitionMs.toDouble(),
          max: maxTransitionMs.toDouble(),
          divisions: 18,
          onChanged: (v) => setState(() => _dragged = v.round()),
          onChangeEnd: (v) async {
            final kind = current;
            setState(() => _dragged = v.round());
            if (kind != null) await apply(kind, v.round());
            if (mounted) setState(() => _dragged = null);
          },
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(l10n.transitionFadeSound),
          value: fadeSound,
          onChanged: (value) =>
              ref.read(_fadeSoundProvider.notifier).state = value,
        ),
      ],
    );
  }
}
