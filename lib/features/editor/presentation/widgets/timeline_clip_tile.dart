import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/editor/data/sample_models.dart';
import 'package:cutter/features/editor/data/sample_project.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

const double _selectedBorderWidth = 2;
const double _unselectedBorderWidth = 1;
const double _dimmedOpacity = 0.5;
const double _draggingOpacity = 0.4;
const double _badgeIconSize = 16;
const double _handleGripWidth = 4;
const double _handleGripHeight = 24;
const double _millisPerSecond = 1000;
const int _minTrimMs = 1;

/// One clip on the timeline: label, selection border plus check, reverse,
/// filter and volume badges, trim handles and long-press drag.
///
/// The long-press drag carries the [SampleClip] as data; the timeline view
/// owns the drop targets and calls the controller.
class TimelineClipTile extends StatefulWidget {
  /// Creates a clip tile.
  const TimelineClipTile({
    required this.clip,
    required this.selected,
    required this.dimmed,
    required this.pixelsPerMs,
    required this.onTap,
    required this.onTrim,
    super.key,
  });

  /// The clip drawn by this tile.
  final SampleClip clip;

  /// Whether the clip is selected.
  final bool selected;

  /// Whether the clip is dimmed, for example on a muted layer.
  final bool dimmed;

  /// Horizontal scale of the timeline.
  final double pixelsPerMs;

  /// Called with the clip id when the tile is tapped.
  final ValueChanged<String> onTap;

  /// Called with the clip id and the new in and out points after a trim.
  final void Function(String id, int inMs, int outMs) onTrim;

  @override
  State<TimelineClipTile> createState() => _TimelineClipTileState();
}

class _TimelineClipTileState extends State<TimelineClipTile> {
  int _startDeltaMs = 0;
  int _endDeltaMs = 0;

  int get _visibleDurationMs {
    final duration = widget.clip.durationMs - _startDeltaMs + _endDeltaMs;
    return duration < _minTrimMs ? _minTrimMs : duration;
  }

  double get _width => _visibleDurationMs * widget.pixelsPerMs;

  void _dragStart(DragUpdateDetails details) {
    final deltaMs = (details.delta.dx / widget.pixelsPerMs).round();
    setState(() => _startDeltaMs += deltaMs);
  }

  void _dragEnd(DragUpdateDetails details) {
    final deltaMs = (details.delta.dx / widget.pixelsPerMs).round();
    setState(() => _endDeltaMs += deltaMs);
  }

  void _commitTrim() {
    final clip = widget.clip;
    final newIn = clip.inMs + _startDeltaMs;
    final newOut = clip.outMs + _endDeltaMs;
    setState(() {
      _startDeltaMs = 0;
      _endDeltaMs = 0;
    });
    if (newIn == clip.inMs && newOut == clip.outMs) return;
    widget.onTrim(clip.id, newIn, newOut);
  }

  String _layerLabel(AppLocalizations l10n) {
    switch (widget.clip.kind) {
      case LayerKind.video:
        return l10n.layerVideo;
      case LayerKind.image:
        return l10n.layerImage;
      case LayerKind.audio:
        return l10n.layerAudio;
    }
  }

  String _seconds(int ms) => (ms / _millisPerSecond).toStringAsFixed(1);

  String? _filterName() {
    final id = widget.clip.filterId;
    if (id == null) return null;
    for (final filter in sampleFilters) {
      if (filter.id == id) return filter.name;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final clip = widget.clip;
    final tile = _buildTile(context);
    final draggable = LongPressDraggable<SampleClip>(
      data: clip,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(opacity: _dimmedOpacity, child: tile),
      ),
      childWhenDragging: Opacity(opacity: _draggingOpacity, child: tile),
      child: tile,
    );
    return Semantics(
      container: true,
      button: true,
      selected: widget.selected,
      label: l10n.clipSemanticLabel(
        clip.name,
        _layerLabel(l10n),
        _seconds(clip.startMs),
        _seconds(clip.durationMs),
      ),
      onTap: () => widget.onTap(clip.id),
      child: ExcludeSemantics(
        child: Opacity(
          opacity: widget.dimmed ? _dimmedOpacity : 1,
          child: draggable,
        ),
      ),
    );
  }

  Widget _buildTile(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final background =
        selected ? scheme.primaryContainer : scheme.secondaryContainer;
    final foreground =
        selected ? scheme.onPrimaryContainer : scheme.onSecondaryContainer;
    final borderColor = selected ? scheme.primary : scheme.outlineVariant;
    final borderWidth =
        selected ? _selectedBorderWidth : _unselectedBorderWidth;
    return GestureDetector(
      onTap: () => widget.onTap(widget.clip.id),
      child: AnimatedContainer(
        duration: motionDuration(context, const Duration(milliseconds: 150)),
        width: _width,
        height: AppSizes.timelineRowHeight - AppSpacing.sm,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadii.small),
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: DefaultTextStyle.merge(
          style: Theme.of(context)
              .textTheme
              .labelMedium!
              .copyWith(color: foreground),
          child: IconTheme(
            data: IconThemeData(color: foreground, size: _badgeIconSize),
            child: Row(
              children: [
                _TrimHandle(
                  label: AppLocalizations.of(context).trimStartHandle,
                  onDrag: _dragStart,
                  onDone: _commitTrim,
                ),
                Expanded(child: ClipRect(child: _content(context))),
                _TrimHandle(
                  label: AppLocalizations.of(context).trimEndHandle,
                  onDrag: _dragEnd,
                  onDone: _commitTrim,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final clip = widget.clip;
    final filterName = _filterName();
    final hasVolumeBadge = clip.kind == LayerKind.audio;
    return Row(
      children: [
        if (widget.selected) ...[
          const Icon(Icons.check_circle),
          const SizedBox(width: AppSpacing.xs),
        ],
        Flexible(
          child: Text(
            clip.name,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
          ),
        ),
        if (clip.reversed) ...[
          const SizedBox(width: AppSpacing.xs),
          const Icon(Icons.fast_rewind),
        ],
        if (filterName != null) ...[
          const SizedBox(width: AppSpacing.xs),
          const Icon(Icons.auto_awesome),
          const SizedBox(width: AppSpacing.xs),
          Text(filterName, maxLines: 1, softWrap: false),
        ],
        if (hasVolumeBadge) ...[
          const SizedBox(width: AppSpacing.xs),
          Icon(clip.volume == 0 ? Icons.volume_off : Icons.volume_up),
        ],
      ],
    );
  }
}

/// A draggable edge of a clip that changes its in or out point.
class _TrimHandle extends StatelessWidget {
  const _TrimHandle({
    required this.label,
    required this.onDrag,
    required this.onDone,
  });

  final String label;
  final GestureDragUpdateCallback onDrag;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: onDrag,
        onHorizontalDragEnd: (_) => onDone(),
        onHorizontalDragCancel: onDone,
        child: SizedBox(
          width: AppSizes.trimHandleWidth,
          height: double.infinity,
          child: Center(
            child: Container(
              width: _handleGripWidth,
              height: _handleGripHeight,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant,
                borderRadius: BorderRadius.circular(AppRadii.extraSmall),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
