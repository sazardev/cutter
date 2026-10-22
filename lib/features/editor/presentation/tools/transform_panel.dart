import 'dart:async';

import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/domain/clip_transform.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/playback_controller.dart';
import 'package:cutter/features/editor/presentation/tools/panel_kit.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double _maxRotation = 180;
const double _maxScaleSlider = 5;

/// Where and how the picture of the selected clip sits: quick actions (fit
/// or fill, quarter turn, mirror, centre, reset) and sliders for scale,
/// rotation and opacity. Moving a slider shows the result live; letting go
/// saves it. Dragging and pinching the picture in the preview does the same.
class TransformPanel extends ConsumerStatefulWidget {
  /// Creates the panel.
  const TransformPanel({super.key});

  @override
  ConsumerState<TransformPanel> createState() => _TransformPanelState();
}

class _TransformPanelState extends ConsumerState<TransformPanel> {
  ClipTransform? _draft;
  String? _clipId;

  void _preview(String clipId, ClipTransform transform) {
    setState(() => _draft = transform);
    ref.read(playbackControllerProvider.notifier).previewTransform(
          clipId,
          transform,
        );
  }

  Future<void> _commit(String clipId, ClipTransform transform) async {
    unawaited(HapticFeedback.selectionClick());
    await ref
        .read(editorControllerProvider.notifier)
        .setTransform(clipId, transform);
    if (mounted) setState(() => _draft = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final clip = ref.watch(editorControllerProvider).valueOrNull?.selectedClip;
    if (clip == null) return const SizedBox.shrink();
    if (_clipId != clip.id) {
      _clipId = clip.id;
      _draft = null;
    }
    final t = _draft ?? clip.transform;

    Widget slider({
      required String label,
      required double value,
      required double min,
      required double max,
      required ClipTransform Function(double v) apply,
      int? divisions,
    }) {
      return SliderTile(
        title: label,
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        onChanged: (v) => _preview(clip.id, apply(v)),
        onChangeEnd: (v) => _commit(clip.id, apply(v)),
      );
    }

    Widget action(IconData icon, String label, VoidCallback? onTap) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        leading: Icon(icon),
        title: Text(label),
        enabled: onTap != null,
        onTap: onTap,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ToolSection(
          icon: Icons.fit_screen_outlined,
          title: l10n.transformSectionFit,
          summary: t.fit == ClipFit.fit ? l10n.fitAction : l10n.fillAction,
          children: [
            OptionTile(
              icon: Icons.fit_screen_outlined,
              title: l10n.fitAction,
              selected: t.fit == ClipFit.fit,
              onTap: () => _commit(clip.id, t.copyWith(fit: ClipFit.fit)),
            ),
            OptionTile(
              icon: Icons.crop_free,
              title: l10n.fillAction,
              selected: t.fit == ClipFit.fill,
              onTap: () => _commit(clip.id, t.copyWith(fit: ClipFit.fill)),
            ),
          ],
        ),
        ToolSection(
          icon: Icons.open_with,
          title: l10n.transformSectionSize,
          summary: '${(t.scale * 100).round()}% · ${t.rotation.round()}°'
              ' · ${(t.opacity * 100).round()}%',
          initiallyExpanded: true,
          children: [
            slider(
              label: l10n.scaleLabel((t.scale * 100).round()),
              value: t.scale,
              min: minClipScale,
              max: _maxScaleSlider,
              apply: (v) => t.copyWith(scale: v),
            ),
            slider(
              label: l10n.rotationLabel(t.rotation.round()),
              value: _signed(t.rotation),
              min: -_maxRotation,
              max: _maxRotation,
              divisions: 72,
              apply: (v) => t.copyWith(rotation: _wrap(v)),
            ),
            slider(
              label: l10n.opacityLabel((t.opacity * 100).round()),
              value: t.opacity,
              min: 0,
              max: 1,
              divisions: 20,
              apply: (v) => t.copyWith(opacity: v),
            ),
            PanelHint(l10n.transformGestureHint),
          ],
        ),
        ToolSection(
          icon: Icons.bolt_outlined,
          title: l10n.transformSectionActions,
          children: [
            action(
              Icons.rotate_90_degrees_cw_outlined,
              l10n.rotateAction,
              () => _commit(
                clip.id,
                t.copyWith(rotation: _wrap(t.rotation + 90)),
              ),
            ),
            action(
              Icons.flip,
              l10n.mirrorAction,
              () => _commit(clip.id, t.copyWith(flipX: !t.flipX)),
            ),
            action(
              Icons.center_focus_strong_outlined,
              l10n.centerAction,
              () => _commit(clip.id, t.copyWith(x: 0, y: 0)),
            ),
            action(
              Icons.restart_alt,
              l10n.resetAction,
              t.isIdentity
                  ? null
                  : () => _commit(clip.id, const ClipTransform()),
            ),
          ],
        ),
      ],
    );
  }

  /// Degrees in 0..360.
  static double _wrap(double degrees) => degrees % 360;

  /// Degrees in -180..180 for the slider.
  static double _signed(double degrees) {
    final d = degrees % 360;
    return d > 180 ? d - 360 : d;
  }
}
