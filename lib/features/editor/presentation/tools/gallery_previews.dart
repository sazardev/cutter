import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cutter/features/editor/domain/animation_preset.dart';
import 'package:cutter/features/editor/domain/clip_transition.dart';
import 'package:cutter/features/editor/presentation/tools/gallery_item.dart';
import 'package:flutter/material.dart';

/// A still picture of what a gallery card does, painted from the theme's
/// colour roles: no engine, no video, nothing that moves, so a whole page of
/// cards costs one paint each.
class GalleryPreview extends StatelessWidget {
  /// Creates the preview of [item].
  const GalleryPreview({required this.item, this.live = false, super.key});

  /// The card's content.
  final GalleryItem item;

  /// Whether an animation card plays its motion in a loop instead of showing
  /// the still; only the card held in the air does, so a page of cards stays
  /// cheap.
  final bool live;

  /// Width of the picture, on the 8dp grid.
  static const double width = 120;

  /// Height of the picture.
  static const double height = 80;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = item;
    if (live && shown is AnimationPresetItem) {
      return _LiveAnimation(preset: shown.preset, scheme: scheme);
    }
    return RepaintBoundary(
      child: CustomPaint(
        size: const Size(width, height),
        painter: switch (item) {
          TransitionItem(:final kind) => _TransitionPainter(kind, scheme),
          FilterItem(:final id) => _EffectPainter(filterId: id, scheme: scheme),
          EffectItem(:final key) => _EffectPainter(effect: key, scheme: scheme),
          AnimationPresetItem(:final preset) =>
            _AnimationPainter(preset, scheme),
        },
      ),
    );
  }
}

/// An animation card playing: the clip comes in, holds, goes out, again.
class _LiveAnimation extends StatefulWidget {
  const _LiveAnimation({required this.preset, required this.scheme});

  final AnimationPreset preset;
  final ColorScheme scheme;

  @override
  State<_LiveAnimation> createState() => _LiveAnimationState();
}

class _LiveAnimationState extends State<_LiveAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _loop,
        builder: (context, _) => CustomPaint(
          size: const Size(GalleryPreview.width, GalleryPreview.height),
          painter: _AnimationPainter(
            widget.preset,
            widget.scheme,
            playing: _loop.value,
          ),
        ),
      ),
    );
  }
}

/// The midpoint of a transition: both clips half way.
class _TransitionPainter extends CustomPainter {
  _TransitionPainter(this.kind, this.scheme);

  final TransitionKind? kind;
  final ColorScheme scheme;

  void _frame(
    Canvas canvas,
    Size size, {
    required Color fill,
    required Color ink,
    required bool round,
    Offset shift = Offset.zero,
    double scale = 1,
    double turn = 0,
    double opacity = 1,
  }) {
    canvas
      ..save()
      ..translate(
        size.width / 2 + shift.dx * size.width,
        size.height / 2 + shift.dy * size.height,
      )
      ..rotate(turn)
      ..scale(scale);
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: size.width,
      height: size.height,
    );
    canvas.drawRect(rect, Paint()..color = fill.withValues(alpha: opacity));
    final shape = Paint()..color = ink.withValues(alpha: opacity);
    if (round) {
      canvas.drawCircle(Offset.zero, size.height * 0.26, shape);
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(0, -size.height * 0.28)
          ..lineTo(size.height * 0.3, size.height * 0.24)
          ..lineTo(-size.height * 0.3, size.height * 0.24)
          ..close(),
        shape,
      );
    }
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas
      ..clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)))
      ..drawRect(rect, Paint()..color = scheme.surfaceContainerHighest);

    void first({
      Offset shift = Offset.zero,
      double scale = 1,
      double turn = 0,
      double opacity = 1,
    }) =>
        _frame(
          canvas,
          size,
          fill: scheme.primary,
          ink: scheme.onPrimary,
          round: true,
          shift: shift,
          scale: scale,
          turn: turn,
          opacity: opacity,
        );
    void second({
      Offset shift = Offset.zero,
      double scale = 1,
      double turn = 0,
      double opacity = 1,
    }) =>
        _frame(
          canvas,
          size,
          fill: scheme.tertiary,
          ink: scheme.onTertiary,
          round: false,
          shift: shift,
          scale: scale,
          turn: turn,
          opacity: opacity,
        );

    switch (kind) {
      case null:
        // No transition: the clips meet at a plain cut.
        first(shift: const Offset(-0.5, 0));
        second(shift: const Offset(0.5, 0));
        canvas
          ..drawLine(
            Offset(size.width / 2, 0),
            Offset(size.width / 2, size.height),
            Paint()
              ..color = scheme.onSurface
              ..strokeWidth = 2,
          )
          ..drawLine(
            Offset.zero,
            Offset(size.width, size.height),
            Paint()
              ..color = scheme.error
              ..strokeWidth = 2,
          );
      case TransitionKind.dip:
        second();
        first(opacity: 0.5);
      case TransitionKind.pushLeft:
        first(shift: const Offset(-0.5, 0));
        second(shift: const Offset(0.5, 0));
      case TransitionKind.pushRight:
        first(shift: const Offset(0.5, 0));
        second(shift: const Offset(-0.5, 0));
      case TransitionKind.pushUp:
        first(shift: const Offset(0, -0.5));
        second(shift: const Offset(0, 0.5));
      case TransitionKind.pushDown:
        first(shift: const Offset(0, 0.5));
        second(shift: const Offset(0, -0.5));
      case TransitionKind.zoomThrough:
        second(scale: 0.8);
        first(scale: 1.5, opacity: 0.5);
      case TransitionKind.spin:
        second(scale: 0.8, turn: 0.35, opacity: 0.85);
        first(scale: 0.8, turn: -0.35, opacity: 0.55);
      case TransitionKind.pop:
        first(opacity: 0.45);
        second(scale: 1.08, opacity: 0.8);
    }
  }

  @override
  bool shouldRepaint(_TransitionPainter old) =>
      old.kind != kind || old.scheme != scheme;
}

// --- Filters and effects ----------------------------------------------------

const double _lumaR = 0.2126;
const double _lumaG = 0.7152;
const double _lumaB = 0.0722;

List<double> _saturation(double s) => [
      _lumaR * (1 - s) + s, _lumaG * (1 - s), _lumaB * (1 - s), 0, 0, //
      _lumaR * (1 - s), _lumaG * (1 - s) + s, _lumaB * (1 - s), 0, 0, //
      _lumaR * (1 - s), _lumaG * (1 - s), _lumaB * (1 - s) + s, 0, 0, //
      0, 0, 0, 1, 0,
    ];

List<double> _tint(
  double r,
  double g,
  double b, [
  double or = 0,
  double og = 0,
  double ob = 0,
]) =>
    [
      r, 0, 0, 0, or, //
      0, g, 0, 0, og, //
      0, 0, b, 0, ob, //
      0, 0, 0, 1, 0,
    ];

List<double> _contrast(double c) =>
    _tint(c, c, c, 128 * (1 - c), 128 * (1 - c), 128 * (1 - c));

/// The matrix of [first] followed by [second].
List<double> _then(List<double> first, List<double> second) {
  final out = List<double>.filled(20, 0);
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 5; col++) {
      var sum = col == 4 ? second[row * 5 + 4] : 0.0;
      for (var k = 0; k < 4; k++) {
        sum += second[row * 5 + k] * first[k * 5 + col];
      }
      out[row * 5 + col] = sum;
    }
  }
  return out;
}

/// A colour matrix close to what the engine's filter [id] does; the card is
/// a hint of the look, the preview of the clip is the truth.
List<double>? _filterMatrix(String id) => switch (id) {
      'mono' => _saturation(0),
      'warm' => _tint(1.12, 1, 0.88, 8, 0, -8),
      'cool' => _tint(0.9, 1, 1.12, -8, 0, 8),
      'vintage' => _then(_saturation(0.6), _tint(1.05, 1, 0.85, 14, 10, 6)),
      'sepia' => [
          0.393, 0.769, 0.189, 0, 0, //
          0.349, 0.686, 0.168, 0, 0, //
          0.272, 0.534, 0.131, 0, 0, //
          0, 0, 0, 1, 0,
        ],
      'noir' => _then(_saturation(0), _contrast(1.5)),
      'vivid' => _saturation(1.7),
      'fade' => _tint(0.85, 0.85, 0.85, 28, 28, 28),
      'cinema' => _then(_tint(1.08, 1, 0.95), _contrast(1.15)),
      'sunset' => _tint(1.2, 0.95, 0.8, 10),
      'invert' => _tint(-1, -1, -1, 255, 255, 255),
      _ => null,
    };

/// A small landscape (sky, sun, two hills) with a filter or an effect on it.
class _EffectPainter extends CustomPainter {
  _EffectPainter({required this.scheme, this.filterId, this.effect});

  final ColorScheme scheme;
  final String? filterId;
  final String? effect;

  double _farHill(double u) => 0.62 + 0.08 * math.sin(u * 6);
  double _nearHill(double u) => 0.8 - 0.1 * math.cos(u * 4 + 1);

  Color _sample(double u, double v) {
    final du = u - 0.7;
    final dv = (v - 0.3) * (96 / 64);
    if (du * du + dv * dv < 0.16 * 0.16) return scheme.tertiary;
    if (v > _nearHill(u)) return scheme.primary;
    if (v > _farHill(u)) return scheme.secondary;
    return Color.lerp(scheme.primaryContainer, scheme.tertiaryContainer, v)!;
  }

  Path _hill(Size size, double Function(double) edge) {
    final path = Path()..moveTo(0, size.height);
    for (var i = 0; i <= 24; i++) {
      final u = i / 24;
      path.lineTo(u * size.width, edge(u) * size.height);
    }
    return path
      ..lineTo(size.width, size.height)
      ..close();
  }

  void _scene(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas
      ..drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero,
            Offset(0, size.height),
            [scheme.primaryContainer, scheme.tertiaryContainer],
          ),
      )
      ..drawCircle(
        Offset(size.width * 0.7, size.height * 0.3),
        size.width * 0.16,
        Paint()..color = scheme.tertiary,
      )
      ..drawPath(_hill(size, _farHill), Paint()..color = scheme.secondary)
      ..drawPath(_hill(size, _nearHill), Paint()..color = scheme.primary);
  }

  void _pixelated(Canvas canvas, Size size) {
    const cols = 12;
    const rows = 8;
    final cell = Size(size.width / cols, size.height / rows);
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        canvas.drawRect(
          Rect.fromLTWH(
            x * cell.width,
            y * cell.height,
            cell.width + 0.5,
            cell.height + 0.5,
          ),
          Paint()..color = _sample((x + 0.5) / cols, (y + 0.5) / rows),
        );
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)));
    final id = filterId;
    if (id != null) {
      final matrix = _filterMatrix(id);
      canvas.saveLayer(
        rect,
        Paint()
          ..colorFilter = matrix == null ? null : ColorFilter.matrix(matrix),
      );
      _scene(canvas, size);
      canvas.restore();
      return;
    }
    switch (effect) {
      case 'blur':
        canvas.saveLayer(
          rect,
          Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
        );
        _scene(canvas, size);
        canvas.restore();
      case 'vignette':
        _scene(canvas, size);
        canvas.drawRect(
          rect,
          Paint()
            ..shader = ui.Gradient.radial(
              rect.center,
              size.width * 0.62,
              [
                scheme.scrim.withValues(alpha: 0),
                scheme.scrim.withValues(alpha: 0.7),
              ],
            ),
        );
      case 'grain':
        _scene(canvas, size);
        final random = math.Random(7);
        final light = Paint()..color = scheme.surface.withValues(alpha: 0.5);
        final dark = Paint()..color = scheme.scrim.withValues(alpha: 0.5);
        for (var i = 0; i < 160; i++) {
          canvas.drawRect(
            Rect.fromLTWH(
              random.nextDouble() * size.width,
              random.nextDouble() * size.height,
              1.5,
              1.5,
            ),
            i.isEven ? light : dark,
          );
        }
      case 'pixelate':
        _pixelated(canvas, size);
      case 'sharpen':
        _scene(canvas, size);
        final edge = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = scheme.onSurface.withValues(alpha: 0.75);
        canvas
          ..drawCircle(
            Offset(size.width * 0.7, size.height * 0.3),
            size.width * 0.16,
            edge,
          )
          ..drawPath(_hill(size, _farHill), edge)
          ..drawPath(_hill(size, _nearHill), edge);
      default:
        _scene(canvas, size);
    }
  }

  @override
  bool shouldRepaint(_EffectPainter old) =>
      old.filterId != filterId || old.effect != effect || old.scheme != scheme;
}

/// An animation preset as two strips of ghost frames: how the clip comes in
/// on the left and how it goes out on the right, the faintest frame first.
class _AnimationPainter extends CustomPainter {
  _AnimationPainter(this.preset, this.scheme, {this.playing});

  final AnimationPreset preset;
  final ColorScheme scheme;

  /// Where a looping preview is, 0 to 1; null for the still picture.
  final double? playing;

  /// How animation [id] looks [p] of the way through an entrance (0 just
  /// started, 1 settled): where the frame is, how big, turned and see-through.
  static ({Offset shift, double scale, double turn, double opacity}) _at(
    String id,
    double p,
  ) {
    final away = 1 - p;
    return switch (id) {
      'fade' => (shift: Offset.zero, scale: 1, turn: 0, opacity: p),
      'slide_left' => (
          shift: Offset(-away, 0),
          scale: 1,
          turn: 0,
          opacity: 1,
        ),
      'slide_right' => (
          shift: Offset(away, 0),
          scale: 1,
          turn: 0,
          opacity: 1,
        ),
      'slide_up' => (shift: Offset(0, away), scale: 1, turn: 0, opacity: 1),
      'slide_down' => (shift: Offset(0, -away), scale: 1, turn: 0, opacity: 1),
      'zoom_in' => (
          shift: Offset.zero,
          scale: 0.4 + 0.6 * p,
          turn: 0,
          opacity: 1,
        ),
      'zoom_out' => (
          shift: Offset.zero,
          scale: 1.6 - 0.6 * p,
          turn: 0,
          opacity: 1,
        ),
      'spin' => (
          shift: Offset.zero,
          scale: 0.4 + 0.6 * p,
          turn: away * math.pi,
          opacity: 1,
        ),
      _ => (
          shift: Offset.zero,
          scale: 0.3 + 0.7 * p,
          turn: 0,
          opacity: 0.4 + 0.6 * p,
        ),
    };
  }

  void _strip(Canvas canvas, Rect area, String? id, {required bool entering}) {
    final base = Rect.fromCenter(
      center: area.center,
      width: area.width * 0.52,
      height: area.height * 0.5,
    );
    if (id == null) {
      // Nothing moves: one still frame, drawn dim.
      canvas.drawRRect(
        RRect.fromRectAndRadius(base, const Radius.circular(4)),
        Paint()..color = scheme.outline.withValues(alpha: 0.5),
      );
      return;
    }
    const steps = [0.0, 0.5, 1.0];
    for (final p in steps) {
      // The exit mirrors the entrance: it ends where the entrance began.
      final progress = entering ? p : 1 - p;
      final look = _at(id, progress);
      // Later frames are drawn stronger, so the eye reads the direction.
      final strength = 0.25 + 0.75 * (entering ? p : 1 - p);
      canvas
        ..save()
        ..clipRect(area)
        ..translate(
          area.center.dx + look.shift.dx * area.width * 0.5,
          area.center.dy + look.shift.dy * area.height * 0.5,
        )
        ..rotate(look.turn)
        ..scale(look.scale)
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: base.width,
              height: base.height,
            ),
            const Radius.circular(4),
          ),
          Paint()
            ..color = (entering ? scheme.primary : scheme.tertiary)
                .withValues(alpha: strength * look.opacity),
        )
        ..restore();
    }
  }

  /// One frame of the loop: in for the first third, held, out for the last.
  void _play(Canvas canvas, Rect area, double t) {
    final entering = preset.animIn;
    final out = preset.animOut;
    final String? id;
    final double progress;
    if (t < 0.3) {
      id = entering;
      progress = t / 0.3;
    } else if (t > 0.7) {
      id = out;
      progress = 1 - (t - 0.7) / 0.3;
    } else {
      id = null;
      progress = 1;
    }
    final base = Rect.fromCenter(
      center: area.center,
      width: area.width * 0.4,
      height: area.height * 0.62,
    );
    final look = id == null
        ? (shift: Offset.zero, scale: 1.0, turn: 0.0, opacity: 1.0)
        : _at(id, progress);
    canvas
      ..save()
      ..clipRect(area)
      ..translate(
        area.center.dx + look.shift.dx * area.width * 0.5,
        area.center.dy + look.shift.dy * area.height * 0.5,
      )
      ..rotate(look.turn)
      ..scale(look.scale)
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: base.width,
            height: base.height,
          ),
          const Radius.circular(4),
        ),
        Paint()..color = scheme.primary.withValues(alpha: look.opacity),
      )
      ..restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas
      ..clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)))
      ..drawRect(rect, Paint()..color = scheme.surfaceContainerHighest);
    final t = playing;
    if (t != null) {
      _play(canvas, rect, t);
      return;
    }
    final half = size.width / 2;
    _strip(
      canvas,
      Rect.fromLTWH(0, 0, half, size.height),
      preset.animIn,
      entering: true,
    );
    _strip(
      canvas,
      Rect.fromLTWH(half, 0, half, size.height),
      preset.animOut,
      entering: false,
    );
    canvas.drawLine(
      Offset(half, size.height * 0.15),
      Offset(half, size.height * 0.85),
      Paint()
        ..color = scheme.outlineVariant
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_AnimationPainter old) =>
      old.preset != preset || old.scheme != scheme || old.playing != playing;
}
