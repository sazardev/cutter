import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/editor/data/sample_models.dart';
import 'package:cutter/features/editor/presentation/editor_controller.dart';
import 'package:cutter/features/editor/presentation/widgets/timeline_clip_tile.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

const double _playheadWidth = 2;
const double _headerNameHeight = 16;
const double _rowHeight = AppSizes.timelineRowHeight + AppSpacing.lg;
const double _clipTop =
    (_rowHeight - (AppSizes.timelineRowHeight - AppSpacing.sm)) / 2;

/// The layered timeline: reorderable layer rows with headers (mute), clips and
/// the playhead line.
class TimelineView extends StatelessWidget {
  /// Creates the timeline for [controller].
  const TimelineView({
    required this.controller,
    required this.onOutcome,
    super.key,
  });

  /// The editor state shown and edited by the timeline.
  final EditorController controller;

  /// Called with the outcome of an edit that was rejected.
  final void Function(EditorOutcome) onOutcome;

  // onReorderItem already corrects the index for the removed item, while the
  // controller follows the ReorderableListView.onReorder convention.
  void _reorder(int oldIndex, int newIndex) {
    controller.reorderLayer(
      oldIndex,
      newIndex > oldIndex ? newIndex + 1 : newIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final layers = controller.project.layers;
        return LayoutBuilder(
          builder: (context, constraints) {
            final clipAreaWidth =
                constraints.maxWidth - AppSizes.layerHeaderWidth;
            final durationMs = controller.project.durationMs;
            final pixelsPerMs =
                durationMs == 0 ? 0.0 : clipAreaWidth / durationMs;
            return SizedBox(
              height: layers.length * _rowHeight,
              child: Stack(
                children: [
                  ReorderableListView(
                    buildDefaultDragHandles: false,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorderItem: _reorder,
                    children: [
                      for (var i = 0; i < layers.length; i++)
                        _LayerRow(
                          key: ValueKey(layers[i].id),
                          index: i,
                          layer: layers[i],
                          controller: controller,
                          pixelsPerMs: pixelsPerMs,
                          onOutcome: onOutcome,
                        ),
                    ],
                  ),
                  Positioned(
                    left: AppSizes.layerHeaderWidth +
                        controller.playheadMs * pixelsPerMs,
                    top: 0,
                    bottom: 0,
                    width: _playheadWidth,
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: ColoredBox(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// One layer: header with drag handle and mute, then the clip area.
class _LayerRow extends StatelessWidget {
  const _LayerRow({
    required this.index,
    required this.layer,
    required this.controller,
    required this.pixelsPerMs,
    required this.onOutcome,
    super.key,
  });

  final int index;
  final SampleLayer layer;
  final EditorController controller;
  final double pixelsPerMs;
  final void Function(EditorOutcome) onOutcome;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _rowHeight,
      child: Row(
        children: [
          _LayerHeader(
            index: index,
            layer: layer,
            onToggleMute: () => controller.toggleLayerMute(layer.id),
          ),
          Expanded(
            child: _ClipArea(
              layer: layer,
              controller: controller,
              pixelsPerMs: pixelsPerMs,
              onOutcome: onOutcome,
            ),
          ),
        ],
      ),
    );
  }
}

String _layerName(AppLocalizations l10n, SampleLayer layer) {
  switch (layer.kind) {
    case LayerKind.video:
      return l10n.layerVideo;
    case LayerKind.image:
      return l10n.layerImage;
    case LayerKind.audio:
      return l10n.layerAudio;
  }
}

/// Layer name, drag handle and mute button.
class _LayerHeader extends StatelessWidget {
  const _LayerHeader({
    required this.index,
    required this.layer,
    required this.onToggleMute,
  });

  final int index;
  final SampleLayer layer;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final name = _layerName(l10n, layer);
    final muteLabel =
        layer.muted ? l10n.unmuteLayer(name) : l10n.muteLayer(name);
    return SizedBox(
      width: AppSizes.layerHeaderWidth,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: _headerNameHeight,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium,
            ),
          ),
          Row(
            children: [
              Semantics(
                label: l10n.dragLayerHandle(name),
                child: ReorderableDragStartListener(
                  index: index,
                  child: SizedBox(
                    width: AppSizes.minTarget,
                    height: AppSizes.minTarget,
                    child: Icon(
                      Icons.drag_handle,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: muteLabel,
                onPressed: onToggleMute,
                constraints: const BoxConstraints.tightFor(
                  width: AppSizes.minTarget,
                  height: AppSizes.minTarget,
                ),
                padding: EdgeInsets.zero,
                icon: Icon(layer.muted ? Icons.volume_off : Icons.volume_up),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The clips of one layer; a drop target for moving clips in time and layers.
class _ClipArea extends StatelessWidget {
  const _ClipArea({
    required this.layer,
    required this.controller,
    required this.pixelsPerMs,
    required this.onOutcome,
  });

  final SampleLayer layer;
  final EditorController controller;
  final double pixelsPerMs;
  final void Function(EditorOutcome) onOutcome;

  void _drop(BuildContext context, DragTargetDetails<SampleClip> details) {
    if (pixelsPerMs <= 0) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return;
    final localX = renderObject.globalToLocal(details.offset).dx;
    final startMs = (localX / pixelsPerMs).round();
    final outcome = controller.moveClip(details.data.id, layer.id, startMs);
    if (outcome != EditorOutcome.ok) onOutcome(outcome);
  }

  void _trim(String id, int inMs, int outMs) {
    final outcome = controller.trim(id, inMs, outMs);
    if (outcome != EditorOutcome.ok) onOutcome(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Builder(
      builder: (areaContext) => DragTarget<SampleClip>(
        onWillAcceptWithDetails: (details) => details.data.kind == layer.kind,
        onAcceptWithDetails: (details) => _drop(areaContext, details),
        builder: (context, candidates, _) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: candidates.isEmpty
                  ? scheme.surfaceContainer
                  : scheme.primaryContainer.withValues(alpha: 0.4),
              border: Border(
                bottom: BorderSide(color: scheme.outlineVariant),
              ),
            ),
            child: Stack(
              children: [
                for (final clip in layer.clips)
                  Positioned(
                    left: clip.startMs * pixelsPerMs,
                    top: _clipTop,
                    child: TimelineClipTile(
                      key: ValueKey(clip.id),
                      clip: clip,
                      selected: controller.selectedClipId == clip.id,
                      dimmed: layer.muted,
                      pixelsPerMs: pixelsPerMs,
                      onTap: controller.select,
                      onTrim: _trim,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
