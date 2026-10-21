import 'dart:math' as math;

import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/data/engine_timeline.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/clip_transform.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/presentation/double_tap.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/playback_controller.dart';
import 'package:cutter/features/editor/presentation/time_format.dart';
import 'package:cutter/features/editor/presentation/tools/editor_tool.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the editor shows only the preview (preview mode).
final previewModeProvider = StateProvider<bool>((ref) => false);

/// How close to the centre, as a fraction of the canvas, a dragged picture
/// snaps onto it.
const double _snapCentre = 0.02;

/// How close to a quarter turn, in degrees, a rotated picture snaps.
const double _snapDegrees = 4;

/// How far, in logical pixels, a finger can be from a handle and still grab
/// it: finger-sized, bigger than the dot that is drawn.
const double _grabRadius = 28;

/// How far above the top edge the rotate handle floats.
const double _rotateReach = 36;

/// How close to the edge of the preview a handle is kept, so that a picture
/// filling the canvas still has handles that can be reached.
const double _edgeInset = 18;

/// What a drag that began on the preview is doing.
enum _Drag {
  /// Nothing: the drag began on empty canvas.
  none,

  /// Moving the picture, and with two fingers also scaling and turning it.
  move,

  /// Scaling from a corner handle.
  corner,

  /// Turning from the rotate handle.
  rotate,
}

/// The handles of a picture in preview coordinates: the four corners (top
/// left, top right, bottom right, bottom left), the rotate handle and the
/// centre.
typedef _Handles = ({List<Offset> corners, Offset rotate, Offset centre});

_Handles _handlesOf(
  ({double cx, double cy, double width, double height, double rotation}) p,
  double k,
  Size size,
) {
  final centre = Offset(p.cx * k, p.cy * k);
  final r = p.rotation * math.pi / 180;
  Offset at(double dx, double dy) =>
      centre +
      Offset(
        dx * math.cos(r) - dy * math.sin(r),
        dx * math.sin(r) + dy * math.cos(r),
      );
  final insetX = math.min(_edgeInset, size.width / 2);
  final insetY = math.min(_edgeInset, size.height / 2);
  Offset keep(Offset o) => Offset(
        o.dx.clamp(insetX, size.width - insetX),
        o.dy.clamp(insetY, size.height - insetY),
      );
  final hw = p.width * k / 2;
  final hh = p.height * k / 2;
  return (
    corners: [
      keep(at(-hw, -hh)),
      keep(at(hw, -hh)),
      keep(at(hw, hh)),
      keep(at(-hw, hh)),
    ],
    rotate: keep(at(0, -hh - _rotateReach)),
    centre: centre,
  );
}

/// The engine's picture of the project, fitted with the canvas shape.
///
/// Playing is left to the play button: a tap never plays or pauses. A tap on
/// a picture selects its clip, a tap on empty canvas clears the selection.
/// Dragging a picture moves it (and selects it first, in one motion); its
/// corner handles scale it, the handle above it turns it, and with two
/// fingers a pinch scales and a twist turns it. Everything is live, snaps to
/// the centre and to quarter turns, and is saved when the fingers lift. The
/// mouse wheel scales.
class PreviewView extends ConsumerStatefulWidget {
  /// Creates the preview; [interactive] is false in preview mode.
  const PreviewView({this.interactive = true, super.key});

  /// Whether pictures can be selected and moved.
  final bool interactive;

  @override
  ConsumerState<PreviewView> createState() => _PreviewViewState();
}

class _PreviewViewState extends ConsumerState<PreviewView> {
  ClipTransform? _start;
  ClipTransform? _live;
  _Drag _drag = _Drag.none;
  final DoubleTap _doubleTap = DoubleTap();
  Offset _grabAt = Offset.zero;

  /// Where the first finger touched down: a drag is only recognised after
  /// the finger has slid some way, so handles are looked for here.
  Offset _downAt = Offset.zero;
  bool _snappedX = false;
  bool _snappedY = false;
  Size _size = Size.zero;

  /// Where [clip] starts in what the preview plays: zero when only that
  /// clip plays, in its own editor.
  int _startOf(Clip clip) {
    final isolated =
        ref.read(playbackControllerProvider.notifier).isolatedClipId;
    return isolated == clip.id ? 0 : clip.startMs;
  }

  bool _showsAt(Clip clip, int playhead) {
    final start = _startOf(clip);
    return playhead >= start && playhead < start + clip.durationMs;
  }

  /// The selected picture when it shows at the playhead.
  Clip? _target() {
    if (!widget.interactive) return null;
    final clip = ref.read(editorControllerProvider).valueOrNull?.selectedClip;
    if (clip == null || clip.kind == MediaKind.audio) return null;
    final playhead = ref.read(playbackControllerProvider).positionMs;
    return _showsAt(clip, playhead) ? clip : null;
  }

  /// The front-most picture under [point], in preview coordinates.
  Clip? _hit(Project project, Offset point, {String? only}) {
    final playhead = ref.read(playbackControllerProvider).positionMs;
    final isolated =
        ref.read(playbackControllerProvider.notifier).isolatedClipId;
    final k = _size.width / project.canvas.width;
    for (final layer in project.layers) {
      if (layer.kind == MediaKind.audio) continue;
      for (final clip in layer.clips) {
        if (isolated != null && clip.id != isolated) continue;
        if (only != null && clip.id != only) continue;
        if (!_showsAt(clip, playhead)) continue;
        final p = placementOf(
          clip,
          clip.transform,
          project.canvas.width.toDouble(),
          project.canvas.height.toDouble(),
        );
        if (p == null) continue;
        final local = _unrotate(point / k, Offset(p.cx, p.cy), p.rotation);
        if (local.dx.abs() <= p.width / 2 && local.dy.abs() <= p.height / 2) {
          return clip;
        }
      }
    }
    return null;
  }

  static Offset _unrotate(Offset point, Offset centre, double degrees) {
    final r = -degrees * math.pi / 180;
    final d = point - centre;
    return Offset(
      d.dx * math.cos(r) - d.dy * math.sin(r),
      d.dx * math.sin(r) + d.dy * math.cos(r),
    );
  }

  void _onTapUp(TapUpDetails details, Project project) {
    final controller = ref.read(editorControllerProvider.notifier);
    final selected =
        ref.read(editorControllerProvider).valueOrNull?.selectedClipId;
    final hit = _hit(project, details.localPosition);
    if (hit == null) {
      if (selected != null) controller.selectClip(null);
    } else if (hit.id != selected) {
      HapticFeedback.selectionClick();
      controller.selectClip(hit.id);
      _doubleTap.tap(hit.id);
    } else if (_doubleTap.tap(hit.id)) {
      // A second tap on the selected picture opens its full options.
      HapticFeedback.selectionClick();
      ref.read(clipDetailsProvider.notifier).state = hit.id;
    }
  }

  /// The handle of the selected picture under [point], or none.
  _Drag _handleAt(Project project, Clip clip, Offset point) {
    final p = placementOf(
      clip,
      clip.transform,
      project.canvas.width.toDouble(),
      project.canvas.height.toDouble(),
    );
    if (p == null) return _Drag.none;
    final handles = _handlesOf(p, _size.width / project.canvas.width, _size);
    if ((handles.rotate - point).distance <= _grabRadius) return _Drag.rotate;
    for (final corner in handles.corners) {
      if ((corner - point).distance <= _grabRadius) return _Drag.corner;
    }
    return _Drag.none;
  }

  void _onScaleStart(ScaleStartDetails details) {
    final project = ref.read(editorControllerProvider).valueOrNull?.project;
    if (project == null) return;
    final controller = ref.read(editorControllerProvider.notifier);
    var clip = _target();
    var mode = _Drag.none;
    final down = details.pointerCount > 1 ? details.localFocalPoint : _downAt;
    if (clip != null && details.pointerCount > 1) {
      // A pinch works from anywhere on the canvas.
      mode = _Drag.move;
    } else if (clip != null) {
      mode = _handleAt(project, clip, down);
    }
    if (mode == _Drag.none) {
      // A finger down on a picture grabs it: the selected one when it is
      // under the finger, else the front-most, selected on the spot.
      final hit = _hit(project, down);
      final selectedHit =
          clip != null && _hit(project, down, only: clip.id) != null;
      if (selectedHit) {
        mode = _Drag.move;
      } else if (hit != null) {
        HapticFeedback.selectionClick();
        controller.selectClip(hit.id);
        clip = _target();
        mode = clip == null ? _Drag.none : _Drag.move;
      }
    }
    if (clip == null || mode == _Drag.none) {
      _drag = _Drag.none;
      return;
    }
    ref.read(playbackControllerProvider.notifier).pause();
    _drag = mode;
    _grabAt = details.localFocalPoint;
    _start = clip.transform;
    _live = clip.transform;
    _snappedX = false;
    _snappedY = false;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final start = _start;
    final clip = _target();
    final project = ref.read(editorControllerProvider).valueOrNull?.project;
    if (start == null || clip == null || project == null || _size.isEmpty) {
      return;
    }
    final next = switch (_drag) {
      _Drag.none => null,
      _Drag.move => _moved(start, details),
      _Drag.corner => _scaledFromCorner(project, clip, start, details),
      _Drag.rotate => _turnedFromHandle(project, clip, start, details),
    };
    if (next == null) return;
    _live = next;
    ref
        .read(playbackControllerProvider.notifier)
        .previewTransform(clip.id, next);
    setState(() {});
  }

  /// The picture moved with the fingers, and scaled and turned by a pinch
  /// and a twist, snapping to the centre and to quarter turns.
  ClipTransform _moved(ClipTransform start, ScaleUpdateDetails details) {
    // Positions follow the finger frame by frame; scale and rotation are
    // measured from where the gesture began.
    var x = (_live?.x ?? start.x) + details.focalPointDelta.dx / _size.width;
    var y = (_live?.y ?? start.y) + details.focalPointDelta.dy / _size.height;
    final snapX = x.abs() < _snapCentre;
    final snapY = y.abs() < _snapCentre;
    if ((snapX && !_snappedX) || (snapY && !_snappedY)) {
      HapticFeedback.selectionClick();
    }
    _snappedX = snapX;
    _snappedY = snapY;
    if (snapX) x = 0;
    if (snapY) y = 0;
    return start.copyWith(
      x: x,
      y: y,
      scale: (start.scale * details.scale).clamp(minClipScale, maxClipScale),
      rotation: _snapTurn(start.rotation + details.rotation * 180 / math.pi),
    );
  }

  /// The centre of the picture with [transform], in preview coordinates.
  Offset _centreOf(Project project, Clip clip, ClipTransform transform) {
    final k = _size.width / project.canvas.width;
    final p = placementOf(
      clip,
      transform,
      project.canvas.width.toDouble(),
      project.canvas.height.toDouble(),
    );
    return p == null ? _size.center(Offset.zero) : Offset(p.cx * k, p.cy * k);
  }

  /// Scale in proportion to how far the finger is from the centre now
  /// against where it was when it grabbed the corner.
  ClipTransform? _scaledFromCorner(
    Project project,
    Clip clip,
    ClipTransform start,
    ScaleUpdateDetails details,
  ) {
    final centre = _centreOf(project, clip, start);
    final before = (_grabAt - centre).distance;
    if (before < 1) return null;
    final ratio = (details.localFocalPoint - centre).distance / before;
    return start.copyWith(
      scale: (start.scale * ratio).clamp(minClipScale, maxClipScale),
    );
  }

  /// Turn by the angle the finger has swept around the centre.
  ClipTransform? _turnedFromHandle(
    Project project,
    Clip clip,
    ClipTransform start,
    ScaleUpdateDetails details,
  ) {
    final centre = _centreOf(project, clip, start);
    final from = _grabAt - centre;
    final to = details.localFocalPoint - centre;
    if (from.distance < 1 || to.distance < 1) return null;
    final swept = math.atan2(to.dy, to.dx) - math.atan2(from.dy, from.dx);
    return start.copyWith(
      rotation: _snapTurn(start.rotation + swept * 180 / math.pi),
    );
  }

  /// [degrees] kept within a turn, snapped to the nearest quarter turn when
  /// close to one.
  double _snapTurn(double degrees) {
    final quarter = (degrees / 90).round() * 90.0;
    final snapped =
        (degrees - quarter).abs() < _snapDegrees ? quarter : degrees;
    if (snapped != degrees && (_live?.rotation ?? 0) != snapped) {
      HapticFeedback.selectionClick();
    }
    return snapped % 360;
  }

  Future<void> _onScaleEnd() async {
    final live = _live;
    final clip = _target();
    _start = null;
    _live = null;
    _drag = _Drag.none;
    setState(() {
      _snappedX = false;
      _snappedY = false;
    });
    if (live == null || clip == null || live == clip.transform) return;
    await ref
        .read(editorControllerProvider.notifier)
        .setTransform(clip.id, live);
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final clip = _target();
    if (clip == null) return;
    final factor = event.scrollDelta.dy > 0 ? 1 / 1.1 : 1.1;
    final next = clip.transform.copyWith(
      scale: (clip.transform.scale * factor).clamp(minClipScale, maxClipScale),
    );
    ref.read(editorControllerProvider.notifier).setTransform(clip.id, next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final playback = ref.watch(playbackControllerProvider);
    final editor = ref.watch(editorControllerProvider).valueOrNull;
    final controller = ref.read(playbackControllerProvider.notifier);
    final project = editor?.project;
    if (project == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final aspect = project.canvas.aspectRatio;
        var width = constraints.maxWidth;
        var height = width / aspect;
        if (height > constraints.maxHeight) {
          height = constraints.maxHeight;
          width = height * aspect;
        }
        _size = Size(width, height);
        final ratio = MediaQuery.devicePixelRatioOf(context);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          controller.setBounds(
            (width * ratio).round(),
            (height * ratio).round(),
          );
        });
        final textureId = playback.textureId;
        final selected = widget.interactive ? editor?.selectedClip : null;
        // The clip whose frame is drawn, or null: a plain value rather than
        // a nullable promoted through a flag.
        final framed = selected != null &&
                selected.kind != MediaKind.audio &&
                _showsAt(selected, playback.positionMs)
            ? selected
            : null;
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: Semantics(
              label: l10n.previewLabel,
              child: Listener(
                onPointerDown: (e) => _downAt = e.localPosition,
                onPointerSignal: _onSignal,
                child: GestureDetector(
                  onTapUp:
                      widget.interactive ? (d) => _onTapUp(d, project) : null,
                  onScaleStart: widget.interactive ? _onScaleStart : null,
                  onScaleUpdate: widget.interactive ? _onScaleUpdate : null,
                  onScaleEnd: widget.interactive ? (_) => _onScaleEnd() : null,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.small),
                    child: ColoredBox(
                      color: scheme.scrim,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (textureId != null)
                            Texture(
                              textureId: textureId,
                              filterQuality: FilterQuality.medium,
                            ),
                          if (framed != null)
                            IgnorePointer(
                              child: CustomPaint(
                                painter: _SelectionPainter(
                                  clip: framed,
                                  transform: _live ?? framed.transform,
                                  canvasWidth: project.canvas.width.toDouble(),
                                  canvasHeight:
                                      project.canvas.height.toDouble(),
                                  scale: width / project.canvas.width,
                                  color: scheme.primary,
                                  ringColor: scheme.onPrimary,
                                  guideColor: scheme.tertiary,
                                  guideX: _snappedX,
                                  guideY: _snappedY,
                                ),
                              ),
                            ),
                          if (playback.unavailable)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: Text(
                                  l10n.previewUnavailable,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: scheme.onSurface,
                                  ),
                                ),
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
        );
      },
    );
  }
}

/// The frame of the selected picture, turned with it, and the centre guides
/// while it snaps.
class _SelectionPainter extends CustomPainter {
  _SelectionPainter({
    required this.clip,
    required this.transform,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.scale,
    required this.color,
    required this.ringColor,
    required this.guideColor,
    required this.guideX,
    required this.guideY,
  });

  final Clip clip;
  final ClipTransform transform;
  final double canvasWidth;
  final double canvasHeight;
  final double scale;
  final Color color;
  final Color ringColor;
  final Color guideColor;
  final bool guideX;
  final bool guideY;

  @override
  void paint(Canvas canvas, Size size) {
    final guide = Paint()
      ..color = guideColor
      ..strokeWidth = 1;
    if (guideX) {
      canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        guide,
      );
    }
    if (guideY) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        guide,
      );
    }
    final p = placementOf(clip, transform, canvasWidth, canvasHeight);
    if (p == null) return;
    final handles = _handlesOf(p, scale, size);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas
      ..save()
      ..translate(p.cx * scale, p.cy * scale)
      ..rotate(p.rotation * math.pi / 180)
      ..drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.width * scale,
          height: p.height * scale,
        ),
        stroke,
      )
      ..restore();
    // The stem from the top edge to the rotate handle.
    final r = p.rotation * math.pi / 180;
    final hh = p.height * scale / 2;
    canvas.drawLine(
      handles.centre + Offset(hh * math.sin(r), -hh * math.cos(r)),
      handles.rotate,
      stroke,
    );
    final fill = Paint()..color = color;
    final ring = Paint()..color = ringColor;
    for (final c in handles.corners) {
      canvas
        ..drawCircle(c, 9, ring)
        ..drawCircle(c, 7, fill);
    }
    canvas
      ..drawCircle(handles.rotate, 11, ring)
      ..drawCircle(handles.rotate, 9, fill)
      ..drawArc(
        Rect.fromCircle(center: handles.rotate, radius: 4),
        -math.pi * 0.2,
        math.pi * 1.5,
        false,
        Paint()
          ..color = ringColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
  }

  @override
  bool shouldRepaint(_SelectionPainter old) =>
      old.transform != transform ||
      old.clip != clip ||
      old.scale != scale ||
      old.guideX != guideX ||
      old.guideY != guideY;
}

/// Play and pause, frame steps, preview mode and the playhead time over the
/// project length.
class TransportBar extends ConsumerWidget {
  /// Creates the transport bar; [withHistory] adds undo and redo, for
  /// narrow windows where the top bar has no room for them.
  const TransportBar({this.withHistory = false, super.key});

  /// Whether undo and redo sit at the ends of the bar.
  final bool withHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final playback = ref.watch(playbackControllerProvider);
    final controller = ref.read(playbackControllerProvider.notifier);
    final duration = controller.durationMs;
    final previewMode = ref.watch(previewModeProvider);
    final editor = ref.watch(editorControllerProvider).valueOrNull;
    final edits = ref.read(editorControllerProvider.notifier);
    final time = Text(
      '${formatTimecode(playback.positionMs, tenths: true)} / '
      '${formatTimecode(duration, tenths: true)}',
      style: theme.textTheme.labelLarge?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        children: [
          if (withHistory)
            IconButton(
              tooltip: l10n.undoAction,
              icon: const Icon(Icons.undo),
              onPressed: editor?.canUndo ?? false ? edits.undo : null,
            ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: time,
            ),
          ),
          IconButton(
            tooltip: l10n.previousFrameAction,
            icon: const Icon(Icons.skip_previous_outlined),
            onPressed: () => controller.stepFrame(forward: false),
          ),
          IconButton.filledTonal(
            tooltip: playback.playing ? l10n.pauseAction : l10n.playAction,
            iconSize: 32,
            icon: Icon(playback.playing ? Icons.pause : Icons.play_arrow),
            onPressed: duration == 0 ? null : controller.toggle,
          ),
          IconButton(
            tooltip: l10n.nextFrameAction,
            icon: const Icon(Icons.skip_next_outlined),
            onPressed: () => controller.stepFrame(forward: true),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: previewMode
                    ? l10n.exitPreviewAction
                    : l10n.previewModeAction,
                icon: Icon(
                  previewMode ? Icons.fullscreen_exit : Icons.fullscreen,
                ),
                onPressed: () =>
                    ref.read(previewModeProvider.notifier).state = !previewMode,
              ),
            ),
          ),
          if (withHistory)
            IconButton(
              tooltip: l10n.redoAction,
              icon: const Icon(Icons.redo),
              onPressed: editor?.canRedo ?? false ? edits.redo : null,
            ),
        ],
      ),
    );
  }
}

/// The scrub bar of preview mode.
class PreviewScrubber extends ConsumerWidget {
  /// Creates the scrubber.
  const PreviewScrubber({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackControllerProvider);
    final controller = ref.read(playbackControllerProvider.notifier);
    final duration = controller.durationMs;
    if (duration == 0) return const SizedBox.shrink();
    return Slider(
      value: playback.positionMs.clamp(0, duration).toDouble(),
      max: duration.toDouble(),
      onChangeStart: (_) => controller.pause(),
      onChanged: (v) => controller.seek(v.round()),
    );
  }
}
