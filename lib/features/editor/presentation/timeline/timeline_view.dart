import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/data/engine_timeline.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/presentation/double_tap.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/missing_media.dart';
import 'package:cutter/features/editor/presentation/playback_controller.dart';
import 'package:cutter/features/editor/presentation/time_format.dart';
import 'package:cutter/features/editor/presentation/timeline/media_previews.dart';
import 'package:cutter/features/editor/presentation/timeline/timeline_geometry.dart';
import 'package:cutter/features/editor/presentation/timeline/timeline_painters.dart';
import 'package:cutter/features/editor/presentation/tools/editor_tool.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double _rulerHeight = 24;
const double _pictureRowHeight = 56;
const double _soundRowHeight = 44;
const double _rowGap = AppSpacing.xs;
const double _headerWidth = 48;
const double _handleWidth = 14;
const double _clipRadius = 6;
const double _playheadWidth = 2;
const double _zoomStep = 1.5;

/// Smallest touch target (48dp).
const double _minTarget = 48;

/// Space between the track headers and time zero: the timeline starts at
/// the left, not under a centred playhead.
const double _lead = AppSpacing.sm;

/// What a pointer is doing to a clip right now.
enum _EditKind { trimStart, trimEnd, move }

class _Edit {
  _Edit(this.kind, this.clip, this.layerId);

  final _EditKind kind;
  final Clip clip;
  String layerId;
  double dx = 0;
  int startMs = 0;
  int inMs = 0;
  int outMs = 0;
  bool snapped = false;
}

/// The multi-layer timeline: a ruler and one row per layer, starting at the
/// left edge. The playhead moves along it; while playing, the view follows
/// once the playhead reaches the middle. Scrolling only looks around: a tap
/// or a drag on the ruler places the playhead. Pinch or the zoom buttons
/// change the scale; selected clips get trim handles; a long press (or a
/// mouse drag) moves a clip, snapping to the playhead and to other clips.
class TimelineView extends ConsumerStatefulWidget {
  /// Creates the timeline; [onAddMedia] opens the import flow and
  /// [onAddLayer] the same flow, putting the media on a new layer.
  const TimelineView({
    required this.onAddMedia,
    required this.onAddLayer,
    super.key,
  });

  /// Opens the import flow.
  final VoidCallback onAddMedia;

  /// Opens the import flow for a new layer.
  final VoidCallback onAddLayer;

  @override
  ConsumerState<TimelineView> createState() => TimelineViewState();
}

/// State of [TimelineView]; public so keyboard shortcuts can zoom it.
class TimelineViewState extends ConsumerState<TimelineView>
    with SingleTickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  final TimelineViewport _viewport = TimelineViewport();

  /// The playhead in milliseconds, smoothed between engine updates while
  /// playing; the playhead line listens to it and to the scroll offset.
  final ValueNotifier<int> _playhead = ValueNotifier<int>(0);
  late final Ticker _ticker;
  double _zoom = defaultZoom;
  double _viewportWidth = 0;
  bool _userScrolling = false;
  final Map<int, Offset> _pointers = {};
  double? _pinchStartDistance;
  double _pinchStartZoom = defaultZoom;
  _Edit? _edit;

  /// While a layer is lifted by a long press: the order the layers show in,
  /// the layer being moved and where it was.
  List<String>? _dragOrder;
  String? _dragLayerId;
  List<String> _dragStartOrder = const [];
  double _dragStartTop = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _scroll.addListener(_syncViewport);
    _playhead.value = ref.read(playbackControllerProvider).positionMs;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _reveal(_playhead.value));
  }

  void _syncViewport() {
    if (_scroll.hasClients) _viewport.update(_scroll.offset, _viewport.width);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scroll
      ..removeListener(_syncViewport)
      ..dispose();
    _viewport.dispose();
    _playhead.dispose();
    super.dispose();
  }

  /// Zooms in one step around the playhead.
  void zoomIn() => _setZoom(_zoom * _zoomStep);

  /// Zooms out one step around the playhead.
  void zoomOut() => _setZoom(_zoom / _zoomStep);

  /// Zooms to one of the ready-made [TimeScale]s.
  void setTimeScale(TimeScale scale) => _setZoom(scale.zoom);

  /// Zooms so a project of [durationMs] fills the timeline.
  void fitProject(int durationMs) =>
      _setZoom(fitZoom(durationMs, _viewportWidth - _lead));

  void _setZoom(double zoom) {
    final ms = ref.read(playbackControllerProvider).positionMs;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    // The playhead stays where it is on screen while the scale changes.
    final screenX = (_lead + ms * _zoom - offset).clamp(0.0, _viewportWidth);
    setState(() => _zoom = zoom.clamp(minZoom, maxZoom));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _lead + ms * _zoom - screenX;
      _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  /// Scrolls so the playhead at [ms] is in view. [follow] is for playing:
  /// the playhead travels to the middle, then the view scrolls with it.
  void _reveal(int ms, {bool follow = false}) {
    if (!_scroll.hasClients) return;
    final x = _lead + ms * _zoom;
    final offset = _scroll.offset;
    final view = _viewportWidth;
    double? target;
    if (follow) {
      if (x - view / 2 > offset) {
        target = x - view / 2;
      } else if (x < offset) {
        target = x - view * 0.2;
      }
    } else if (x < offset + 8 || x > offset + view - 8) {
      target = x - view / 2;
    }
    if (target == null) return;
    _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
  }

  /// While playing, draws the playhead between engine updates so it moves
  /// every frame.
  void _onTick(Duration _) {
    final playback = ref.read(playbackControllerProvider);
    if (!playback.playing) return;
    final since = playback.updatedAt == null
        ? 0
        : DateTime.now().difference(playback.updatedAt!).inMilliseconds;
    final ms = playback.positionMs + since;
    _playhead.value = ms;
    if (!_userScrolling) _reveal(ms, follow: true);
  }

  /// Looking around never moves the playhead or stops playback; it only
  /// stops the view from following until the finger lifts.
  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userScrolling = true;
    } else if (notification is ScrollEndNotification) {
      _userScrolling = false;
    }
    return false;
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 2) {
      final points = _pointers.values.toList();
      _pinchStartDistance = (points[0] - points[1]).distance;
      _pinchStartZoom = _zoom;
      setState(() {});
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    final start = _pinchStartDistance;
    if (_pointers.length == 2 && start != null && start > 0) {
      final points = _pointers.values.toList();
      final distance = (points[0] - points[1]).distance;
      _setZoom(_pinchStartZoom * distance / start);
    }
  }

  void _onPointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2 && _pinchStartDistance != null) {
      setState(() => _pinchStartDistance = null);
    }
  }

  // --- Clip taps -----------------------------------------------------------

  final DoubleTap _doubleTap = DoubleTap();

  /// A tap selects the clip at once and shows the short bar; a second tap on
  /// it opens the full options.
  void _tapClip(Clip clip) {
    ref.read(editorControllerProvider.notifier).selectClip(clip.id);
    if (_doubleTap.tap(clip.id)) {
      HapticFeedback.selectionClick();
      ref.read(clipDetailsProvider.notifier).state = clip.id;
    }
  }

  // --- Layer order ----------------------------------------------------------

  /// The layers in the order they are shown: the project's, or the one being
  /// tried while a layer is lifted.
  List<Layer> _shownLayers(Project project) {
    final order = _dragOrder;
    if (order == null) return project.layers;
    final byId = {for (final layer in project.layers) layer.id: layer};
    return [
      for (final id in order)
        if (byId[id] != null) byId[id]!,
    ];
  }

  void _liftLayer(Project project, Layer layer) {
    HapticFeedback.mediumImpact();
    var top = 0.0;
    for (final other in project.layers) {
      if (other.id == layer.id) break;
      top += _rowHeight(other) + _rowGap;
    }
    setState(() {
      _dragLayerId = layer.id;
      _dragStartOrder = [for (final l in project.layers) l.id];
      _dragOrder = _dragStartOrder;
      _dragStartTop = top;
    });
  }

  /// Moves the lifted layer to where the finger is: it swaps places with
  /// each layer whose middle it crosses.
  void _moveLayer(Project project, double dy) {
    final id = _dragLayerId;
    if (id == null) return;
    final byId = {for (final layer in project.layers) layer.id: layer};
    final lifted = byId[id];
    if (lifted == null) return;
    final centre = _dragStartTop + _rowHeight(lifted) / 2 + dy;
    final others = <Layer>[];
    var index = 0;
    var top = 0.0;
    // Middles are measured where the layers were when it was lifted.
    for (final otherId in _dragStartOrder) {
      final other = byId[otherId];
      if (other == null) continue;
      if (otherId != id) {
        others.add(other);
        if (top + _rowHeight(other) / 2 < centre) index++;
      }
      top += _rowHeight(other) + _rowGap;
    }
    final next = [for (final other in others) other.id]..insert(index, id);
    if (!_sameOrder(next, _dragOrder ?? const [])) {
      HapticFeedback.selectionClick();
      setState(() => _dragOrder = next);
    }
  }

  Future<void> _dropLayer() async {
    final order = _dragOrder;
    final changed = order != null && !_sameOrder(order, _dragStartOrder);
    if (changed) {
      await ref.read(editorControllerProvider.notifier).reorderLayers(order);
    }
    if (!mounted) return;
    setState(() {
      _dragOrder = null;
      _dragLayerId = null;
    });
  }

  static bool _sameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // --- Clip edits -----------------------------------------------------------

  void _beginEdit(_EditKind kind, Clip clip, String layerId) {
    final playback = ref.read(playbackControllerProvider);
    if (playback.playing) ref.read(playbackControllerProvider.notifier).pause();
    ref.read(editorControllerProvider.notifier).selectClip(clip.id);
    setState(() {
      _edit = _Edit(kind, clip, layerId)
        ..startMs = clip.startMs
        ..inMs = clip.inPointMs
        ..outMs = clip.outPointMs;
    });
    HapticFeedback.selectionClick();
  }

  void _updateEdit(
    Project project, {
    double? delta,
    double? totalDx,
    double? pointerY,
  }) {
    final edit = _edit;
    if (edit == null) return;
    edit.dx = totalDx ?? edit.dx + (delta ?? 0);
    final deltaMs = (edit.dx / _zoom).round();
    final clip = edit.clip;
    final playhead = ref.read(playbackControllerProvider).positionMs;
    final targets = snapTargets(project, playhead, clip.id);
    var snapped = false;
    switch (edit.kind) {
      case _EditKind.trimStart:
        final raw = trimStart(clip, deltaMs);
        final rawStart =
            clip.startMs + ((raw.inMs - clip.inPointMs) / clip.speed).round();
        final snap = snapTime(rawStart, targets, _zoom);
        final fixed = trimStart(clip, snap.ms - clip.startMs);
        edit
          ..inMs = fixed.inMs
          ..outMs = fixed.outMs
          ..startMs = clip.startMs +
              ((fixed.inMs - clip.inPointMs) / clip.speed).round();
        snapped = snap.snapped;
      case _EditKind.trimEnd:
        final raw = trimEnd(clip, deltaMs);
        final rawEnd =
            clip.startMs + ((raw.outMs - raw.inMs) / clip.speed).round();
        final snap = snapTime(rawEnd, targets, _zoom);
        final fixed = trimEnd(clip, snap.ms - clip.range.endMs);
        edit
          ..inMs = fixed.inMs
          ..outMs = fixed.outMs;
        snapped = snap.snapped;
      case _EditKind.move:
        final rawStart = math.max(0, clip.startMs + deltaMs);
        final byStart = snapTime(rawStart, targets, _zoom);
        final byEnd = snapTime(rawStart + clip.durationMs, targets, _zoom);
        if (byStart.snapped) {
          edit.startMs = byStart.ms;
        } else if (byEnd.snapped) {
          edit.startMs = byEnd.ms - clip.durationMs;
        } else {
          edit.startMs = rawStart;
        }
        snapped = byStart.snapped || byEnd.snapped;
        if (pointerY != null) {
          final target = _layerAtY(project, pointerY);
          if (target != null && target.kind == clip.kind) {
            edit.layerId = target.id;
          }
        }
    }
    if (snapped && !edit.snapped) HapticFeedback.selectionClick();
    edit.snapped = snapped;
    setState(() {});
  }

  Future<void> _endEdit() async {
    final edit = _edit;
    if (edit == null) return;
    setState(() => _edit = null);
    final controller = ref.read(editorControllerProvider.notifier);
    final clip = edit.clip;
    switch (edit.kind) {
      case _EditKind.trimStart:
      case _EditKind.trimEnd:
        if (edit.inMs == clip.inPointMs && edit.outMs == clip.outPointMs) {
          return;
        }
        await controller.trimClip(
          clip.id,
          inPointMs: edit.inMs,
          outPointMs: edit.outMs,
        );
      case _EditKind.move:
        if (edit.startMs == clip.startMs && edit.layerId == clip.layerId) {
          return;
        }
        await controller.moveClip(clip.id, edit.layerId, edit.startMs);
    }
  }

  Layer? _layerAtY(Project project, double y) {
    var top = 0.0;
    for (final layer in project.layers) {
      final height = _rowHeight(layer) + _rowGap;
      if (y >= top && y < top + height) return layer;
      top += height;
    }
    return null;
  }

  /// The clip as drawn: its stored geometry, or the one being dragged.
  Clip _shown(Clip clip) {
    final edit = _edit;
    if (edit == null || edit.clip.id != clip.id) return clip;
    return clip.copyWith(
      startMs: edit.startMs,
      inPointMs: edit.inMs,
      outPointMs: edit.outMs,
      layerId: edit.layerId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final editor = ref.watch(editorControllerProvider).valueOrNull;
    if (editor == null) return const SizedBox.shrink();
    final project = editor.project;
    final playing =
        ref.watch(playbackControllerProvider.select((p) => p.playing));
    ref.listen(playbackControllerProvider, (previous, next) {
      if (next.playing && !_ticker.isActive) _ticker.start();
      if (!next.playing && _ticker.isActive) _ticker.stop();
      if (!next.playing) {
        _playhead.value = next.positionMs;
        if (!_userScrolling && _edit == null) _reveal(next.positionMs);
      }
    });

    if (project.layers.every((l) => l.clips.isEmpty)) {
      return _EmptyTimeline(onAddMedia: widget.onAddMedia);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportWidth = constraints.maxWidth - _headerWidth;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _viewport.update(
            _scroll.hasClients ? _scroll.offset : 0,
            _viewportWidth,
          );
        });
        const lead = _lead;
        // Room after the last clip, so its end can be brought to the middle.
        final contentWidth = math.max(
          _viewportWidth,
          lead + project.durationMs * _zoom + _viewportWidth / 2,
        );
        final pinching = _pinchStartDistance != null;
        return Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: Semantics(
            label: l10n.timelineLabel,
            child: Column(
              children: [
                SizedBox(
                  height: _rulerHeight,
                  child: Row(
                    children: [
                      SizedBox(
                        width: _headerWidth,
                        child: _TimeScaleMenu(
                          zoom: _zoom,
                          onScale: setTimeScale,
                          onFit: () => fitProject(project.durationMs),
                          child: _ScaleLabel(zoom: _zoom),
                        ),
                      ),
                      Expanded(
                        child: _Ruler(
                          scroll: _scroll,
                          zoom: _zoom,
                          leadPx: lead,
                          onSeek: (ms) => ref
                              .read(playbackControllerProvider.notifier)
                              .seek(ms),
                          onScrubStart: () => ref
                              .read(playbackControllerProvider.notifier)
                              .pause(),
                          onZoomIn: zoomIn,
                          onZoomOut: zoomOut,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      // A mouse or trackpad drags the timeline like a finger
                      // does; Flutter leaves those devices out by default.
                      ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(
                          dragDevices: {
                            PointerDeviceKind.touch,
                            PointerDeviceKind.mouse,
                            PointerDeviceKind.trackpad,
                            PointerDeviceKind.stylus,
                          },
                        ),
                        child: SingleChildScrollView(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: _headerWidth,
                                child: Column(
                                  children: [
                                    for (final layer in _shownLayers(project))
                                      _LayerHeader(
                                        key: ValueKey(layer.id),
                                        layer: layer,
                                        lifted: layer.id == _dragLayerId,
                                        onLift: () =>
                                            _liftLayer(project, layer),
                                        onMove: (dy) => _moveLayer(project, dy),
                                        onDrop: _dropLayer,
                                      ),
                                    // A layer takes the kind of what is put on
                                    // it, so adding one starts from the media.
                                    Tooltip(
                                      message: l10n.addLayerAction,
                                      child: IconButton.filledTonal(
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(
                                          Icons.library_add_outlined,
                                          size: 20,
                                        ),
                                        onPressed: widget.onAddLayer,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: NotificationListener<ScrollNotification>(
                                  onNotification: _onScroll,
                                  child: SingleChildScrollView(
                                    controller: _scroll,
                                    scrollDirection: Axis.horizontal,
                                    physics: pinching
                                        ? const NeverScrollableScrollPhysics()
                                        : const ClampingScrollPhysics(),
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onTap: () => ref
                                          .read(
                                            editorControllerProvider.notifier,
                                          )
                                          .selectClip(null),
                                      child: SizedBox(
                                        width: contentWidth,
                                        child: Column(
                                          children: [
                                            for (final layer
                                                in _shownLayers(project))
                                              _trackRow(
                                                project,
                                                layer,
                                                editor.selectedClipId,
                                                lead,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned.fill(
                        left: _headerWidth,
                        child: IgnorePointer(
                          child: ClipRect(
                            child: ListenableBuilder(
                              listenable:
                                  Listenable.merge([_scroll, _playhead]),
                              builder: (context, _) {
                                final offset =
                                    _scroll.hasClients ? _scroll.offset : 0.0;
                                final x =
                                    lead + _playhead.value * _zoom - offset;
                                return Stack(
                                  children: [
                                    Positioned(
                                      left: x - _playheadWidth / 2,
                                      top: 0,
                                      bottom: 0,
                                      width: _playheadWidth,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: scheme.onSurface,
                                          borderRadius:
                                              BorderRadius.circular(1),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: AppSpacing.sm,
                        bottom: AppSpacing.sm,
                        child: _TimelineTools(
                          playing: playing,
                          onZoomIn: zoomIn,
                          onZoomOut: zoomOut,
                          onAddMedia: widget.onAddMedia,
                          zoom: _zoom,
                          onScale: setTimeScale,
                          onFit: () => fitProject(project.durationMs),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _trackRow(
    Project project,
    Layer layer,
    String? selectedId,
    double lead,
  ) {
    // Plain values rather than a promoted nullable: the dragged clip and
    // where it is going, or nulls.
    final edit = _edit;
    final movingId =
        edit != null && edit.kind == _EditKind.move ? edit.clip.id : null;
    final ghostLayerId = movingId != null ? edit?.layerId : null;
    final ghost = movingId != null && edit != null ? _shown(edit.clip) : null;
    final moving = movingId != null;
    Widget positioned(Clip clip, Widget child) => Positioned(
          left: lead + clip.startMs * _zoom,
          top: 0,
          bottom: 0,
          width: math.max(_handleWidth * 2, clip.durationMs * _zoom),
          child: child,
        );
    final liftedRow = layer.id == _dragLayerId;
    return Padding(
      padding: const EdgeInsets.only(bottom: _rowGap),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: liftedRow
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.14)
              : null,
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        child: SizedBox(
          height: _rowHeight(layer),
          child: Stack(
            clipBehavior: ui.Clip.none,
            children: [
              for (final clip in layer.clips)
                // The dragged clip keeps its place in the tree so its gesture
                // survives; a ghost shows where it will land.
                positioned(
                  moving ? clip : _shown(clip),
                  _ClipTile(
                    key: ValueKey(clip.id),
                    viewport: _viewport,
                    contentLeft:
                        lead + (moving ? clip : _shown(clip)).startMs * _zoom,
                    clip: moving ? clip : _shown(clip),
                    layer: layer,
                    zoom: _zoom,
                    selected: clip.id == selectedId,
                    dimmed: movingId == clip.id,
                    onTap: () => _tapClip(clip),
                    onTrimStart: (d) => _handleTrim(
                      _EditKind.trimStart,
                      clip,
                      layer,
                      d,
                      project,
                    ),
                    onTrimEnd: (d) =>
                        _handleTrim(_EditKind.trimEnd, clip, layer, d, project),
                    onTrimDone: _endEdit,
                    onMoveStart: () =>
                        _beginEdit(_EditKind.move, clip, layer.id),
                    onMoveUpdate: (totalDx, localY) => _updateEdit(
                      project,
                      totalDx: totalDx,
                      pointerY: _rowTop(project, layer) + localY,
                    ),
                    onMoveEnd: _endEdit,
                  ),
                ),
              if (ghost != null && ghostLayerId == layer.id)
                positioned(
                  ghost,
                  IgnorePointer(
                    child: _ClipTile(
                      viewport: _viewport,
                      contentLeft: lead + ghost.startMs * _zoom,
                      clip: ghost,
                      layer: layer,
                      zoom: _zoom,
                      selected: true,
                      dimmed: false,
                      onTap: () {},
                      onTrimStart: (_) {},
                      onTrimEnd: (_) {},
                      onTrimDone: () {},
                      onMoveStart: () {},
                      onMoveUpdate: (_, __) {},
                      onMoveEnd: () {},
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleTrim(
    _EditKind kind,
    Clip clip,
    Layer layer,
    Offset delta,
    Project project,
  ) {
    if (_edit == null) _beginEdit(kind, clip, layer.id);
    _updateEdit(project, delta: delta.dx);
  }

  static double _rowTop(Project project, Layer layer) {
    var top = 0.0;
    for (final other in project.layers) {
      if (other.id == layer.id) break;
      top += _rowHeight(other) + _rowGap;
    }
    return top;
  }
}

double _rowHeight(Layer layer) =>
    layer.kind == MediaKind.audio ? _soundRowHeight : _pictureRowHeight;

class _Ruler extends StatelessWidget {
  const _Ruler({
    required this.scroll,
    required this.zoom,
    required this.leadPx,
    required this.onSeek,
    required this.onScrubStart,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final ScrollController scroll;
  final double zoom;
  final double leadPx;
  final ValueChanged<int> onSeek;
  final VoidCallback onScrubStart;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  /// The wheel over the ruler moves the timeline sideways, whichever way
  /// the wheel turns; with Ctrl (or Cmd) held it zooms instead.
  void _onWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final wheel = event as PointerScrollEvent;
      final keyboard = HardwareKeyboard.instance;
      if (keyboard.isControlPressed || keyboard.isMetaPressed) {
        if (wheel.scrollDelta.dy < 0) {
          onZoomIn();
        } else if (wheel.scrollDelta.dy > 0) {
          onZoomOut();
        }
        return;
      }
      if (!scroll.hasClients) return;
      final delta = wheel.scrollDelta.dx != 0
          ? wheel.scrollDelta.dx
          : wheel.scrollDelta.dy;
      scroll.jumpTo(
        (scroll.offset + delta).clamp(0, scroll.position.maxScrollExtent),
      );
    });
  }

  int _msAt(double x) {
    final offset = scroll.hasClients ? scroll.offset : 0.0;
    final ms = ((x + offset - leadPx) / zoom).round();
    return ms < 0 ? 0 : ms;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      label: l10n.rulerLabel,
      child: Listener(
        onPointerSignal: _onWheel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => onSeek(_msAt(details.localPosition.dx)),
          onHorizontalDragStart: (details) {
            onScrubStart();
            onSeek(_msAt(details.localPosition.dx));
          },
          onHorizontalDragUpdate: (details) =>
              onSeek(_msAt(details.localPosition.dx)),
          child: ListenableBuilder(
            listenable: scroll,
            builder: (context, _) => CustomPaint(
              size: Size.infinite,
              painter: RulerPainter(
                offset: scroll.hasClients ? scroll.offset : 0,
                zoom: zoom,
                leadPx: leadPx,
                tickColor: theme.colorScheme.outline,
                labelStyle: theme.textTheme.labelSmall!.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textDirection: Directionality.of(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LayerHeader extends ConsumerWidget {
  const _LayerHeader({
    required this.layer,
    required this.lifted,
    required this.onLift,
    required this.onMove,
    required this.onDrop,
    super.key,
  });

  final Layer layer;

  /// Whether this layer is the one being moved.
  final bool lifted;

  /// A long press lifts the layer; dragging up or down moves it among the
  /// others and letting go keeps the order.
  final VoidCallback onLift;
  final ValueChanged<double> onMove;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final audible = layer.kind != MediaKind.image;
    return Padding(
      padding: const EdgeInsets.only(bottom: _rowGap),
      child: Semantics(
        customSemanticsActions: {
          CustomSemanticsAction(label: l10n.layerMoveUpAction): () =>
              ref.read(editorControllerProvider.notifier).moveLayer(
                    layer.id,
                    -1,
                  ),
          CustomSemanticsAction(label: l10n.layerMoveDownAction): () =>
              ref.read(editorControllerProvider.notifier).moveLayer(
                    layer.id,
                    1,
                  ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPressStart: (_) => onLift(),
          onLongPressMoveUpdate: (d) => onMove(d.offsetFromOrigin.dy),
          onLongPressEnd: (_) => onDrop(),
          onLongPressCancel: onDrop,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: _rowHeight(layer),
            decoration: BoxDecoration(
              color: lifted ? scheme.primaryContainer : null,
              borderRadius: BorderRadius.circular(AppRadii.small),
            ),
            child: Center(
              child: audible
                  // The hint shows on hover only: a long press lifts the layer.
                  ? Tooltip(
                      triggerMode: TooltipTriggerMode.manual,
                      message: layer.muted
                          ? l10n.unmuteLayerAction
                          : l10n.muteLayerAction,
                      child: IconButton(
                        isSelected: layer.muted,
                        icon: Icon(
                          layer.kind == MediaKind.audio
                              ? Icons.music_note_outlined
                              : Icons.volume_up_outlined,
                        ),
                        selectedIcon:
                            Icon(Icons.volume_off, color: scheme.error),
                        onPressed: () => ref
                            .read(editorControllerProvider.notifier)
                            .setLayerMuted(layer.id, muted: !layer.muted),
                      ),
                    )
                  : Icon(
                      Icons.image_outlined,
                      color: scheme.onSurfaceVariant,
                      semanticLabel: l10n.layerKindImage,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClipTile extends ConsumerWidget {
  const _ClipTile({
    required this.viewport,
    required this.contentLeft,
    required this.clip,
    required this.layer,
    required this.zoom,
    required this.selected,
    required this.dimmed,
    required this.onTap,
    required this.onTrimStart,
    required this.onTrimEnd,
    required this.onTrimDone,
    required this.onMoveStart,
    required this.onMoveUpdate,
    required this.onMoveEnd,
    super.key,
  });

  final TimelineViewport viewport;
  final double contentLeft;
  final Clip clip;
  final Layer layer;
  final double zoom;
  final bool selected;

  /// True for a clip left behind while its ghost is dragged.
  final bool dimmed;
  final VoidCallback onTap;
  final ValueChanged<Offset> onTrimStart;
  final ValueChanged<Offset> onTrimEnd;
  final VoidCallback onTrimDone;
  final VoidCallback onMoveStart;

  /// Called with the horizontal distance from where the drag started and
  /// the pointer's height inside the clip.
  final void Function(double totalDx, double localY) onMoveUpdate;
  final VoidCallback onMoveEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (background, foreground) = switch (clip.kind) {
      MediaKind.video => (scheme.surfaceContainerHighest, scheme.onSurface),
      MediaKind.image => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      MediaKind.audio => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer
        ),
    };
    final content = clip.kind == MediaKind.audio
        ? _Waveform(
            clip: clip,
            zoom: zoom,
            color: foreground,
            viewport: viewport,
            contentLeft: contentLeft,
          )
        : CustomPaint(
            painter: FilmstripPainter(
              store: ref.watch(thumbnailStoreProvider),
              clip: clip,
              zoom: zoom,
              placeholder: background,
              viewport: viewport,
              contentLeft: contentLeft,
            ),
          );
    final missing = ref.watch(
      missingSourcesProvider.select(
        (sources) => sources.valueOrNull?.contains(clip.sourceUri) ?? false,
      ),
    );
    final badges = [
      if (missing) Icons.link_off,
      if (clip.reversed) Icons.fast_rewind,
      if (clip.filterId != null || clip.adjustments.values.any((v) => v != 0))
        Icons.auto_awesome,
      if (clip.volume == 0 || layer.muted) Icons.volume_off,
    ];
    final tile = AnimatedOpacity(
      opacity: dimmed ? 0.35 : 1,
      duration: const Duration(milliseconds: 90),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: missing ? scheme.errorContainer : background,
          borderRadius: BorderRadius.circular(_clipRadius),
          border: Border.all(
            color: missing
                ? scheme.error
                : selected
                    ? scheme.primary
                    : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_clipRadius - 1),
          child: Stack(
            fit: StackFit.expand,
            children: [
              content,
              if (selected || badges.isNotEmpty)
                Positioned(
                  left: selected ? _handleWidth + 2 : AppSpacing.xs,
                  top: 2,
                  child: _ClipBadge(
                    text: selected
                        ? formatTimecode(clip.durationMs, tenths: true)
                        : null,
                    icons: badges,
                  ),
                ),
              if (selected) ...[
                _TrimHandle(
                  alignment: Alignment.centerLeft,
                  icon: Icons.chevron_left,
                  onDrag: onTrimStart,
                  onDone: onTrimDone,
                ),
                _TrimHandle(
                  alignment: Alignment.centerRight,
                  icon: Icons.chevron_right,
                  onDrag: onTrimEnd,
                  onDone: onTrimDone,
                ),
              ],
            ],
          ),
        ),
      ),
    );
    // Each clip paints into its own layer: scrolling and the moving
    // playhead then move pictures instead of repainting them.
    return RepaintBoundary(
      child: Semantics(
        button: true,
        selected: selected,
        label: (missing ? '${l10n.missingMediaClip}. ' : '') +
            l10n.clipSemanticsLabel(
          _kindLabel(l10n, clip.kind),
          formatTimelineTime(clip.startMs),
          formatTimelineTime(clip.durationMs),
        ),
        child: GestureDetector(
          onTap: onTap,
          onLongPressStart: (_) => onMoveStart(),
          onLongPressMoveUpdate: (d) =>
              onMoveUpdate(d.offsetFromOrigin.dx, d.localPosition.dy),
          onLongPressEnd: (_) => onMoveEnd(),
          child: _MouseMove(
            onStart: onMoveStart,
            onUpdate: onMoveUpdate,
            onEnd: onMoveEnd,
            child: tile,
          ),
        ),
      ),
    );
  }

  static String _kindLabel(AppLocalizations l10n, MediaKind kind) =>
      switch (kind) {
        MediaKind.video => l10n.layerKindVideo,
        MediaKind.image => l10n.layerKindImage,
        MediaKind.audio => l10n.layerKindAudio,
      };
}

/// Dragging a clip with a mouse moves it at once; touch needs a long press
/// so that a swipe still scrolls the timeline.
class _MouseMove extends StatefulWidget {
  const _MouseMove({
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.child,
  });

  final VoidCallback onStart;
  final void Function(double totalDx, double localY) onUpdate;
  final VoidCallback onEnd;
  final Widget child;

  @override
  State<_MouseMove> createState() => _MouseMoveState();
}

class _MouseMoveState extends State<_MouseMove> {
  double _startX = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      supportedDevices: const {PointerDeviceKind.mouse},
      onPanStart: (d) {
        _startX = d.localPosition.dx;
        widget.onStart();
      },
      onPanUpdate: (d) =>
          widget.onUpdate(d.localPosition.dx - _startX, d.localPosition.dy),
      onPanEnd: (_) => widget.onEnd(),
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: widget.child),
    );
  }
}

class _TrimHandle extends StatelessWidget {
  const _TrimHandle({
    required this.alignment,
    required this.icon,
    required this.onDrag,
    required this.onDone,
  });

  final Alignment alignment;
  final IconData icon;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: alignment,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) => onDrag(d.delta),
          onHorizontalDragEnd: (_) => onDone(),
          child: Container(
            width: _handleWidth,
            color: scheme.primary,
            alignment: Alignment.center,
            child: Icon(icon, size: 14, color: scheme.onPrimary),
          ),
        ),
      ),
    );
  }
}

class _ClipBadge extends StatelessWidget {
  const _ClipBadge({required this.text, required this.icons});

  final String? text;
  final List<IconData> icons;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppRadii.small / 2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final icon in icons)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Icon(icon, size: 12, color: scheme.onSurface),
              ),
            if (text != null)
              Text(
                text!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Waveform extends ConsumerWidget {
  const _Waveform({
    required this.clip,
    required this.zoom,
    required this.color,
    required this.viewport,
    required this.contentLeft,
  });

  final Clip clip;
  final double zoom;
  final Color color;
  final TimelineViewport viewport;
  final double contentLeft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peaks = ref
        .watch(
          waveformProvider(
            (filePathOf(clip.sourceUri), clip.sourceDurationMs),
          ),
        )
        .valueOrNull;
    return CustomPaint(
      painter: WaveformPainter(
        peaks: peaks ?? const [],
        clip: clip,
        zoom: zoom,
        color: color.withValues(alpha: 0.8),
        viewport: viewport,
        contentLeft: contentLeft,
      ),
    );
  }
}

/// The distance between two ruler marks as a short text: "50 ms", "1 s",
/// "5 min".
String _stepText(AppLocalizations l10n, double zoom) {
  final step = rulerStepMs(zoom);
  if (step < 1000) return l10n.timeUnitMilliseconds(step);
  if (step < 60000) return l10n.timeUnitSeconds(step ~/ 1000);
  return l10n.timeUnitMinutes(step ~/ 60000);
}

/// The ruler corner: what one mark is worth at the current zoom.
class _ScaleLabel extends StatelessWidget {
  const _ScaleLabel({required this.zoom});

  final double zoom;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: l10n.timeScaleLabel(_stepText(l10n, zoom)),
      excludeSemantics: true,
      child: Center(
        child: Text(
          _stepText(l10n, zoom),
          maxLines: 1,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// The time scale button of the floating tools: icon and current unit.
class _ScaleButton extends StatelessWidget {
  const _ScaleButton({required this.zoom});

  final double zoom;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: l10n.timeScaleLabel(_stepText(l10n, zoom)),
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: _minTarget,
          minHeight: _minTarget,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.straighten, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Text(
                _stepText(l10n, zoom),
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the time scale menu offers; the first three line up with
/// [TimeScale].
enum _ScaleChoice { milliseconds, seconds, minutes, fit }

/// The menu of ready-made time scales around [child]: milliseconds,
/// seconds, minutes, or fit the whole project. The scale closest to the
/// current zoom is marked.
class _TimeScaleMenu extends StatelessWidget {
  const _TimeScaleMenu({
    required this.zoom,
    required this.onScale,
    required this.onFit,
    required this.child,
  });

  final double zoom;
  final ValueChanged<TimeScale> onScale;
  final VoidCallback onFit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final current = TimeScale.nearest(zoom);
    String name(TimeScale scale) => switch (scale) {
          TimeScale.milliseconds => l10n.timeScaleMilliseconds,
          TimeScale.seconds => l10n.timeScaleSeconds,
          TimeScale.minutes => l10n.timeScaleMinutes,
        };
    return PopupMenuButton<_ScaleChoice>(
      tooltip: l10n.timeScaleTitle,
      padding: EdgeInsets.zero,
      onSelected: (choice) {
        switch (choice) {
          case _ScaleChoice.milliseconds:
            onScale(TimeScale.milliseconds);
          case _ScaleChoice.seconds:
            onScale(TimeScale.seconds);
          case _ScaleChoice.minutes:
            onScale(TimeScale.minutes);
          case _ScaleChoice.fit:
            onFit();
        }
      },
      itemBuilder: (context) => [
        for (final scale in TimeScale.values)
          CheckedPopupMenuItem<_ScaleChoice>(
            value: _ScaleChoice.values[scale.index],
            checked: scale == current,
            child: Text(name(scale)),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<_ScaleChoice>(
          value: _ScaleChoice.fit,
          child: Text(l10n.timeScaleFit),
        ),
      ],
      child: child,
    );
  }
}

class _TimelineTools extends StatelessWidget {
  const _TimelineTools({
    required this.playing,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onAddMedia,
    required this.zoom,
    required this.onScale,
    required this.onFit,
  });

  final bool playing;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onAddMedia;
  final double zoom;
  final ValueChanged<TimeScale> onScale;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: const StadiumBorder(),
      elevation: 2,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TimeScaleMenu(
            zoom: zoom,
            onScale: onScale,
            onFit: onFit,
            child: _ScaleButton(zoom: zoom),
          ),
          IconButton(
            tooltip: l10n.zoomOutAction,
            icon: const Icon(Icons.zoom_out),
            onPressed: onZoomOut,
          ),
          IconButton(
            tooltip: l10n.zoomInAction,
            icon: const Icon(Icons.zoom_in),
            onPressed: onZoomIn,
          ),
          IconButton.filled(
            tooltip: l10n.importMediaAction,
            icon: const Icon(Icons.add),
            onPressed: onAddMedia,
          ),
        ],
      ),
    );
  }
}

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline({required this.onAddMedia});

  final VoidCallback onAddMedia;

  /// Below this height only the button shows, so an open tool panel never
  /// squeezes the empty state into an overflow.
  static const double _fullHeight = 200;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final button = FilledButton.icon(
      onPressed: onAddMedia,
      icon: const Icon(Icons.add_photo_alternate_outlined),
      label: Text(l10n.importMediaAction),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < _fullHeight) {
          return Center(child: button);
        }
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.movie_creation_outlined,
                    size: 40,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.emptyTimelineTitle,
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l10n.emptyTimelineBody,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  button,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
