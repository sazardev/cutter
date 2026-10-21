import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/clip_crop.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const List<double> _speeds = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4];
const List<int> _imageSeconds = [1, 2, 3, 5, 10];
const double _maxCropEdge = 0.45;
const int _maxFadeMs = 5000;

/// The selected clip, rebuilt when it changes.
Clip? _clip(WidgetRef ref) =>
    ref.watch(editorControllerProvider).valueOrNull?.selectedClip;

String _speedLabel(double speed) {
  final text = speed == speed.roundToDouble()
      ? speed.toStringAsFixed(0)
      : speed.toString();
  return '$text×';
}

/// Playback speed of the selected clip, from a quarter to four times.
class SpeedPanel extends ConsumerWidget {
  /// Creates the panel.
  const SpeedPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final clip = _clip(ref);
    if (clip == null) return const SizedBox.shrink();
    final controller = ref.read(editorControllerProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            for (final speed in _speeds)
              ChoiceChip(
                label: Text(_speedLabel(speed)),
                selected: clip.speed == speed,
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  controller.setSpeed(clip.id, speed);
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.speedSummary(
            _speedLabel(clip.speed),
            (clip.durationMs / 1000).toStringAsFixed(1),
          ),
          style: theme.textTheme.bodyMedium,
        ),
        if (clip.speed != 1)
          Text(
            l10n.speedMutesSound,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// Keeps part of the picture: a shape to cut to, or each edge by hand.
class CropPanel extends ConsumerStatefulWidget {
  /// Creates the panel.
  const CropPanel({super.key});

  @override
  ConsumerState<CropPanel> createState() => _CropPanelState();
}

class _CropPanelState extends ConsumerState<CropPanel> {
  ClipCrop? _draft;
  String? _clipId;

  Future<void> _commit(String clipId, ClipCrop crop) async {
    await ref.read(editorControllerProvider.notifier).setCrop(clipId, crop);
    if (mounted) setState(() => _draft = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final editor = ref.watch(editorControllerProvider).valueOrNull;
    final clip = editor?.selectedClip;
    if (editor == null || clip == null) return const SizedBox.shrink();
    if (_clipId != clip.id) {
      _clipId = clip.id;
      _draft = null;
    }
    final crop = _draft ?? clip.crop;
    final shapes = <(String, double?)>[
      (l10n.cropFree, null),
      (l10n.cropCanvas, editor.project.canvas.aspectRatio),
      ('9:16', 9 / 16),
      ('1:1', 1),
      ('4:5', 4 / 5),
      ('16:9', 16 / 9),
    ];
    Widget edge(String label, double value, ClipCrop Function(double v) set) {
      return Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(0, _maxCropEdge),
              max: _maxCropEdge,
              onChanged: (v) => setState(() => _draft = set(v)),
              onChangeEnd: (v) => _commit(clip.id, set(v)),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            for (final (label, aspect) in shapes)
              ActionChip(
                label: Text(label),
                onPressed: clip.sourceWidth <= 0
                    ? null
                    : () => _commit(
                          clip.id,
                          aspect == null
                              ? const ClipCrop()
                              : ClipCrop.centred(
                                  aspect,
                                  clip.sourceWidth,
                                  clip.sourceHeight,
                                ),
                        ),
              ),
          ],
        ),
        edge(l10n.cropLeft, crop.left, (v) => _with(crop, left: v)),
        edge(l10n.cropRight, crop.right, (v) => _with(crop, right: v)),
        edge(l10n.cropTop, crop.top, (v) => _with(crop, top: v)),
        edge(l10n.cropBottom, crop.bottom, (v) => _with(crop, bottom: v)),
      ],
    );
  }

  static ClipCrop _with(
    ClipCrop c, {
    double? left,
    double? top,
    double? right,
    double? bottom,
  }) =>
      ClipCrop(
        left: left ?? c.left,
        top: top ?? c.top,
        right: right ?? c.right,
        bottom: bottom ?? c.bottom,
      );
}

/// Sound fades at the start and end of the selected clip.
class FadesPanel extends ConsumerStatefulWidget {
  /// Creates the panel.
  const FadesPanel({super.key});

  @override
  ConsumerState<FadesPanel> createState() => _FadesPanelState();
}

class _FadesPanelState extends ConsumerState<FadesPanel> {
  (int, int)? _draft;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final clip = _clip(ref);
    if (clip == null) return const SizedBox.shrink();
    final limit = (clip.durationMs ~/ 2).clamp(0, _maxFadeMs);
    final (inMs, outMs) = _draft ?? (clip.fadeInMs, clip.fadeOutMs);
    final controller = ref.read(editorControllerProvider.notifier);
    Future<void> commit(int i, int o) async {
      await controller.setFades(clip.id, inMs: i, outMs: o);
      if (mounted) setState(() => _draft = null);
    }

    Widget fade(
      String Function(String seconds) label,
      int value,
      (int, int) Function(int v) set,
    ) {
      return Row(
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label((value / 1000).toStringAsFixed(1)),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(0, limit).toDouble(),
              max: limit.toDouble().clamp(1, double.infinity),
              divisions: limit > 0 ? (limit ~/ 100).clamp(1, 50) : null,
              onChanged: limit == 0
                  ? null
                  : (v) => setState(() => _draft = set(v.round())),
              onChangeEnd: (v) {
                final (i, o) = set(v.round());
                commit(i, o);
              },
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        fade(l10n.fadeInLabel, inMs, (v) => (v, outMs)),
        fade(l10n.fadeOutLabel, outMs, (v) => (inMs, v)),
      ],
    );
  }
}

/// How long the selected image shows.
class ImageDurationPanel extends ConsumerStatefulWidget {
  /// Creates the panel.
  const ImageDurationPanel({super.key});

  @override
  ConsumerState<ImageDurationPanel> createState() => _ImageDurationPanelState();
}

class _ImageDurationPanelState extends ConsumerState<ImageDurationPanel> {
  double? _draft;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final clip = _clip(ref);
    if (clip == null) return const SizedBox.shrink();
    final controller = ref.read(editorControllerProvider.notifier);
    final seconds = _draft ?? clip.durationMs / 1000;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.imageDurationLabel(seconds.toStringAsFixed(1)),
          style: theme.textTheme.bodyMedium,
        ),
        Slider(
          value: seconds.clamp(0.5, 30),
          min: 0.5,
          max: 30,
          divisions: 59,
          onChanged: (v) => setState(() => _draft = v),
          onChangeEnd: (v) async {
            await controller.setImageDuration(clip.id, (v * 1000).round());
            if (mounted) setState(() => _draft = null);
          },
        ),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final s in _imageSeconds)
              ActionChip(
                label: Text(l10n.secondsShort(s)),
                onPressed: () => controller.setImageDuration(clip.id, s * 1000),
              ),
          ],
        ),
      ],
    );
  }
}
