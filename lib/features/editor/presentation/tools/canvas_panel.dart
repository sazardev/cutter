import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/domain/canvas.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double _tileHeight = 72;
const List<int> _frameRates = [24, 30, 60];

/// The shape and frame rate of the canvas. Each shape is drawn to scale so
/// the choice reads at a glance; pictures keep their relative place.
class CanvasPanel extends ConsumerWidget {
  /// Creates the panel.
  const CanvasPanel({super.key});

  String _label(AppLocalizations l10n, CanvasPreset preset) => switch (preset) {
        CanvasPreset.portrait => l10n.canvasPortrait,
        CanvasPreset.landscape => l10n.canvasLandscape,
        CanvasPreset.square => l10n.canvasSquare,
        CanvasPreset.feed => l10n.canvasFeed,
      };

  String _ratio(CanvasPreset preset) => switch (preset) {
        CanvasPreset.portrait => '9:16',
        CanvasPreset.landscape => '16:9',
        CanvasPreset.square => '1:1',
        CanvasPreset.feed => '4:5',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final project = ref.watch(editorControllerProvider).valueOrNull?.project;
    if (project == null) return const SizedBox.shrink();
    final canvas = project.canvas;
    final controller = ref.read(editorControllerProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final preset in CanvasPreset.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: Semantics(
                    button: true,
                    selected: canvas.preset == preset,
                    label: '${_label(l10n, preset)} ${_ratio(preset)}',
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadii.medium),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        controller.setCanvas(preset.canvas(fps: canvas.fps));
                      },
                      child: Ink(
                        decoration: BoxDecoration(
                          color: canvas.preset == preset
                              ? scheme.primaryContainer
                              : scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(AppRadii.medium),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          child: Column(
                            children: [
                              SizedBox(
                                height: _tileHeight * 0.55,
                                child: Center(
                                  child: AspectRatio(
                                    aspectRatio: preset.width / preset.height,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: canvas.preset == preset
                                              ? scheme.onPrimaryContainer
                                              : scheme.onSurfaceVariant,
                                          width: 2,
                                        ),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                _ratio(preset),
                                style: theme.textTheme.labelLarge,
                              ),
                              Text(
                                _label(l10n, preset),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(l10n.exportFpsLabel, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        SegmentedButton<int>(
          segments: [
            for (final fps in _frameRates)
              ButtonSegment(value: fps, label: Text(l10n.exportFpsValue(fps))),
          ],
          selected: {canvas.fps},
          emptySelectionAllowed: true,
          onSelectionChanged: (s) {
            if (s.isEmpty) return;
            controller.setCanvas(canvas.copyWith(fps: s.single));
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.canvasSize(canvas.width, canvas.height),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
