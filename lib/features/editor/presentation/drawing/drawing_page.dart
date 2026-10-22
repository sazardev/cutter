import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/domain/clip_drawing.dart';
import 'package:cutter/features/editor/presentation/drawing/drawing_painter.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The colours of the drawing palette, as `0xAARRGGBB`. They are the user's
/// ink, not interface colours, so they do not come from the theme.
const drawingPalette = <int>[
  0xFFFFFFFF,
  0xFF000000,
  0xFFE53935,
  0xFFFB8C00,
  0xFFFDD835,
  0xFF43A047,
  0xFF1E88E5,
  0xFF8E24AA,
  0xFFEC407A,
];

/// Key of the surface the strokes are drawn on, for tests.
const drawingCanvasKey = ValueKey('drawing-canvas');

/// How thick a new stroke starts, as a fraction of the canvas short side.
const _defaultWidth = 0.012;

/// Opens the drawing screen. With [clipId] it edits that drawing clip;
/// otherwise it makes a new drawing that starts at [startMs] when done.
Future<void> openDrawing(
  BuildContext context, {
  String? clipId,
  int startMs = 0,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => DrawingPage(clipId: clipId, startMs: startMs),
    ),
  );
}

/// Draw with a finger over a frame of the project's canvas shape, with a
/// palette, a thickness, an eraser and undo. Done saves the strokes as a
/// picture on the timeline; they are kept to be edited again.
class DrawingPage extends ConsumerStatefulWidget {
  /// Creates the screen.
  const DrawingPage({this.clipId, this.startMs = 0, super.key});

  /// The drawing clip being edited, or null for a new drawing.
  final String? clipId;

  /// Where a new drawing starts on the timeline.
  final int startMs;

  @override
  ConsumerState<DrawingPage> createState() => _DrawingPageState();
}

class _DrawingPageState extends ConsumerState<DrawingPage> {
  ClipDrawing _drawing = ClipDrawing.empty;
  List<double>? _current;
  int _color = drawingPalette[2];
  double _width = _defaultWidth;
  bool _erasing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final id = widget.clipId;
    if (id != null) {
      final clip =
          ref.read(editorControllerProvider).valueOrNull?.project.clipById(id);
      _drawing = clip?.drawing ?? ClipDrawing.empty;
    }
  }

  DrawingStroke _stroke(List<double> points) => DrawingStroke(
        color: _color,
        width: _width,
        erase: _erasing,
        points: points,
      );

  /// The drawing with the stroke being drawn on top.
  ClipDrawing get _shown =>
      _current == null ? _drawing : _drawing.plus(_stroke(_current!));

  void _add(Offset position, Size size) {
    final x = (position.dx / size.width).clamp(0.0, 1.0);
    final y = (position.dy / size.height).clamp(0.0, 1.0);
    setState(() => _current = [...?_current, x, y]);
  }

  void _end() {
    final points = _current;
    if (points == null) return;
    setState(() {
      _drawing = _drawing.plus(_stroke(points));
      _current = null;
    });
  }

  Future<void> _done() async {
    if (_drawing.isBlank) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    final controller = ref.read(editorControllerProvider.notifier);
    final id = widget.clipId;
    if (id == null) {
      await controller.addDrawing(_drawing, widget.startMs);
    } else {
      await controller.setDrawing(id, _drawing);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final canvas =
        ref.watch(editorControllerProvider).valueOrNull?.project.canvas;
    final ratio = canvas == null ? 9 / 16 : canvas.width / canvas.height;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.drawingTitle),
        actions: [
          IconButton(
            tooltip: l10n.drawingUndo,
            icon: const Icon(Icons.undo),
            onPressed: _drawing.strokes.isEmpty
                ? null
                : () => setState(() => _drawing = _drawing.withoutLast()),
          ),
          IconButton(
            tooltip: l10n.drawingClear,
            icon: const Icon(Icons.delete_outline),
            onPressed: _drawing.strokes.isEmpty
                ? null
                : () => setState(() => _drawing = ClipDrawing.empty),
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: FilledButton(
              onPressed: _saving ? null : _done,
              child: Text(l10n.drawingDone),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Center(
                child: AspectRatio(
                  aspectRatio: ratio,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.medium),
                    child: ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final size = box.biggest;
                          return Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (e) => _add(e.localPosition, size),
                            onPointerMove: (e) => _add(e.localPosition, size),
                            onPointerUp: (_) => _end(),
                            onPointerCancel: (_) => _end(),
                            child: CustomPaint(
                              key: drawingCanvasKey,
                              size: size,
                              painter: DrawingPainter(_shown),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Material(
            color: scheme.surfaceContainer,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(
                              value: false,
                              icon: const Icon(Icons.brush),
                              label: Text(l10n.drawingBrush),
                            ),
                            ButtonSegment(
                              value: true,
                              icon: const Icon(Icons.auto_fix_normal),
                              label: Text(l10n.drawingEraser),
                            ),
                          ],
                          selected: {_erasing},
                          onSelectionChanged: (s) =>
                              setState(() => _erasing = s.first),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Semantics(
                            label: l10n.drawingThickness,
                            child: Slider(
                              value: _width,
                              min: minStrokeWidth,
                              max: maxStrokeWidth,
                              onChanged: (v) => setState(() => _width = v),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final color in drawingPalette)
                            _Swatch(
                              color: color,
                              label: l10n.drawingColor,
                              selected: !_erasing && color == _color,
                              onTap: () => setState(() {
                                _color = color;
                                _erasing = false;
                              }),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final int color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Container(
            width: 48,
            height: 48,
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.primary : Colors.transparent,
                width: 3,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color(color),
                border: Border.all(color: scheme.outlineVariant),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
