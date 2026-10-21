import 'dart:async';

import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/domain/clip_transform.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/playback_controller.dart';
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
    final theme = Theme.of(context);
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
      return Row(
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: (v) => _preview(clip.id, apply(v)),
              onChangeEnd: (v) => _commit(clip.id, apply(v)),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<ClipFit>(
          segments: [
            ButtonSegment(
              value: ClipFit.fit,
              icon: const Icon(Icons.fit_screen_outlined),
              label: Text(l10n.fitAction),
            ),
            ButtonSegment(
              value: ClipFit.fill,
              icon: const Icon(Icons.crop_free),
              label: Text(l10n.fillAction),
            ),
          ],
          selected: {t.fit},
          onSelectionChanged: (s) =>
              _commit(clip.id, t.copyWith(fit: s.single)),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            ActionChip(
              avatar: const Icon(Icons.rotate_90_degrees_cw_outlined, size: 18),
              label: Text(l10n.rotateAction),
              onPressed: () => _commit(
                clip.id,
                t.copyWith(rotation: _wrap(t.rotation + 90)),
              ),
            ),
            ActionChip(
              avatar: const Icon(Icons.flip, size: 18),
              label: Text(l10n.mirrorAction),
              onPressed: () => _commit(clip.id, t.copyWith(flipX: !t.flipX)),
            ),
            ActionChip(
              avatar: const Icon(Icons.center_focus_strong_outlined, size: 18),
              label: Text(l10n.centerAction),
              onPressed: () => _commit(clip.id, t.copyWith(x: 0, y: 0)),
            ),
            ActionChip(
              avatar: const Icon(Icons.restart_alt, size: 18),
              label: Text(l10n.resetAction),
              onPressed: t.isIdentity
                  ? null
                  : () => _commit(clip.id, const ClipTransform()),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
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
        Text(
          l10n.transformGestureHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
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
