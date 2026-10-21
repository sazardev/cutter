import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/presentation/layout/editor_layout.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Thickness of the divider: roomy enough for a finger.
const double _handleThickness = 24;

/// Height of the transport bar kept next to the preview.
const double _transportHeight = 48;

/// What a pane is laid out at while it is squeezed away, so its contents
/// never see a size too small to hold them.
const double _minLayout = 160;

/// A pane that stays above this share is not "focused away".
const double _snapEdge = 0.06;

/// The preview and the timeline side by side or one over the other, with a
/// divider between them: drag it to give one more room, or tap the button at
/// its centre to go from balanced to the preview filling the space, to the
/// timeline filling it, and back. The divider keeps out of the way until it
/// is touched, and the choice is remembered.
class EditorSplit extends ConsumerStatefulWidget {
  /// Creates the split. [transport] sits next to the preview and stays
  /// visible when the timeline is focused (it is inside the preview side
  /// when the timeline is [TimelinePosition.side]).
  const EditorSplit({
    required this.position,
    required this.preview,
    required this.transport,
    required this.timeline,
    super.key,
  });

  /// Where the timeline sits.
  final TimelinePosition position;

  /// The picture.
  final Widget preview;

  /// Play, step and time.
  final Widget transport;

  /// The timeline.
  final Widget timeline;

  @override
  ConsumerState<EditorSplit> createState() => _EditorSplitState();
}

class _EditorSplitState extends ConsumerState<EditorSplit> {
  /// The share while a drag is going on; null otherwise.
  double? _dragging;

  bool get _horizontal => widget.position == TimelinePosition.side;

  void _drag(double delta, double room) {
    if (room <= 0) return;
    final share = ref.read(editorLayoutProvider).previewShare;
    final previewFirst = widget.position != TimelinePosition.top;
    final change = (previewFirst ? delta : -delta) / room;
    setState(() => _dragging = ((_dragging ?? share) + change).clamp(0.0, 1.0));
  }

  Future<void> _release() async {
    var share = _dragging;
    if (share == null) return;
    // Near an edge the divider snaps to it: that pane is focused.
    if (share < _snapEdge) share = 0;
    if (share > 1 - _snapEdge) share = 1;
    setState(() => _dragging = null);
    await ref.read(editorLayoutProvider.notifier).setPreviewShare(share);
  }

  /// Balanced, then the preview alone, then the timeline alone.
  double _nextShare(double share) {
    if (share >= 1 - _snapEdge) return 0;
    if (share <= _snapEdge) return EditorLayoutPrefs.defaultPreviewShare;
    return 1;
  }

  Widget _pane(Widget child, double size) {
    final natural = size < _minLayout ? _minLayout : size;
    return ClipRect(
      child: SizedBox(
        width: _horizontal ? size : null,
        height: _horizontal ? null : size,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          // Along the split the pane may be squeezed below its natural
          // size; across it the parent's width or height applies.
          minWidth: _horizontal ? 0 : null,
          minHeight: _horizontal ? null : 0,
          maxWidth: _horizontal ? natural : null,
          maxHeight: _horizontal ? null : natural,
          child: SizedBox(
            width: _horizontal ? natural : null,
            height: _horizontal ? null : natural,
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final stored = ref.watch(editorLayoutProvider).previewShare;
    final share = _dragging ?? stored;
    final next = _nextShare(share);
    final hint = next == 1
        ? l10n.splitFocusPreview
        : next == 0
            ? l10n.splitFocusTimeline
            : l10n.splitBalance;
    return LayoutBuilder(
      builder: (context, constraints) {
        final total =
            _horizontal ? constraints.maxWidth : constraints.maxHeight;
        // The transport takes a row of its own, except beside the timeline
        // where it belongs to the preview side.
        final fixed = _handleThickness + (_horizontal ? 0 : _transportHeight);
        final room = (total - fixed).clamp(0.0, double.infinity);
        final previewSize = room * share;
        final timelineSize = room - previewSize;
        final handle = _SplitHandle(
          horizontal: _horizontal,
          hint: hint,
          label: l10n.splitHandleLabel,
          focused: share <= _snapEdge || share >= 1 - _snapEdge,
          dragging: _dragging != null,
          onDrag: (delta) => _drag(delta, room),
          onRelease: _release,
          onTap: () {
            HapticFeedback.selectionClick();
            ref.read(editorLayoutProvider.notifier).setPreviewShare(next);
          },
        );
        return switch (widget.position) {
          TimelinePosition.bottom => Column(
              children: [
                _pane(widget.preview, previewSize),
                SizedBox(height: _transportHeight, child: widget.transport),
                handle,
                _pane(widget.timeline, timelineSize),
              ],
            ),
          TimelinePosition.top => Column(
              children: [
                _pane(widget.timeline, timelineSize),
                handle,
                _pane(widget.preview, previewSize),
                SizedBox(height: _transportHeight, child: widget.transport),
              ],
            ),
          TimelinePosition.side => Row(
              children: [
                _pane(
                  Column(
                    children: [
                      Expanded(child: widget.preview),
                      SizedBox(
                        height: _transportHeight,
                        child: widget.transport,
                      ),
                    ],
                  ),
                  previewSize,
                ),
                handle,
                _pane(widget.timeline, timelineSize),
              ],
            ),
        };
      },
    );
  }
}

/// The divider: a hairline with a small pill at its centre that grows when
/// touched; drag anywhere on it to resize, tap the pill to focus a pane.
class _SplitHandle extends StatefulWidget {
  const _SplitHandle({
    required this.horizontal,
    required this.hint,
    required this.label,
    required this.focused,
    required this.dragging,
    required this.onDrag,
    required this.onRelease,
    required this.onTap,
  });

  final bool horizontal;
  final String hint;
  final String label;

  /// Whether one pane fills the space.
  final bool focused;
  final bool dragging;
  final ValueChanged<double> onDrag;
  final VoidCallback onRelease;
  final VoidCallback onTap;

  @override
  State<_SplitHandle> createState() => _SplitHandleState();
}

class _SplitHandleState extends State<_SplitHandle> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _hovering || widget.dragging;
    final horizontal = widget.horizontal;
    // Half hidden at rest so it never gets in the way.
    final opacity = active ? 1.0 : 0.45;
    final pill = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: horizontal ? 8 : (active || widget.focused ? 56 : 40),
      height: horizontal ? (active || widget.focused ? 56 : 40) : 8,
      decoration: BoxDecoration(
        color: active ? scheme.primary : scheme.onSurfaceVariant,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
    );
    return Semantics(
      label: widget.label,
      hint: widget.hint,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: horizontal
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate:
              horizontal ? null : (d) => widget.onDrag(d.delta.dy),
          onVerticalDragEnd: horizontal ? null : (_) => widget.onRelease(),
          onVerticalDragCancel: horizontal ? null : widget.onRelease,
          onHorizontalDragUpdate:
              horizontal ? (d) => widget.onDrag(d.delta.dx) : null,
          onHorizontalDragEnd: horizontal ? (_) => widget.onRelease() : null,
          onHorizontalDragCancel: horizontal ? widget.onRelease : null,
          child: SizedBox(
            width: horizontal ? _handleThickness : null,
            height: horizontal ? null : _handleThickness,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: horizontal ? 1 : null,
                  height: horizontal ? null : 1,
                  color: scheme.outlineVariant,
                ),
                Opacity(
                  opacity: opacity,
                  child: Tooltip(
                    message: widget.hint,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadii.small),
                      onTap: widget.onTap,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: pill,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
