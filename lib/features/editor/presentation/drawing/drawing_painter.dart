import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cutter/features/editor/domain/clip_drawing.dart';
import 'package:flutter/rendering.dart';

/// Paints [drawing] over [size]: strokes in order, erasers rubbing out what
/// is under them. Points are fractions of [size], and thickness is a
/// fraction of its short side, so the same drawing paints alike on the
/// screen and in the PNG.
void paintDrawing(Canvas canvas, Size size, ClipDrawing drawing) {
  // A layer of its own, so an eraser clears strokes but not what is behind
  // the drawing.
  canvas.saveLayer(Offset.zero & size, Paint());
  final side = size.shortestSide;
  for (final stroke in drawing.strokes) {
    if (stroke.length == 0) continue;
    final paint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = stroke.width * side
      ..color = ui.Color(stroke.color);
    if (stroke.erase) paint.blendMode = BlendMode.clear;
    Offset at(int i) => Offset(
          stroke.points[2 * i] * size.width,
          stroke.points[2 * i + 1] * size.height,
        );
    if (stroke.length == 1) {
      canvas.drawPoints(ui.PointMode.points, [at(0)], paint);
      continue;
    }
    // Curves through the midpoints of the segments: smooth, however
    // coarse the finger's samples.
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < stroke.length - 1; i++) {
      final mid = (at(i) + at(i + 1)) / 2;
      path.quadraticBezierTo(at(i).dx, at(i).dy, mid.dx, mid.dy);
    }
    path.lineTo(at(stroke.length - 1).dx, at(stroke.length - 1).dy);
    canvas.drawPath(path, paint);
  }
  canvas.restore();
}

/// Draws a [ClipDrawing] on screen.
class DrawingPainter extends CustomPainter {
  /// Creates a painter for [drawing].
  const DrawingPainter(this.drawing);

  /// What to paint.
  final ClipDrawing drawing;

  @override
  void paint(Canvas canvas, Size size) => paintDrawing(canvas, size, drawing);

  @override
  bool shouldRepaint(DrawingPainter old) => old.drawing != drawing;
}

/// [drawing] as a PNG of [width] x [height] pixels with a transparent
/// background.
Future<Uint8List> renderDrawingPng(
  ClipDrawing drawing,
  int width,
  int height,
) async {
  final recorder = ui.PictureRecorder();
  final size = Size(width.toDouble(), height.toDouble());
  paintDrawing(Canvas(recorder), size, drawing);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('cannot encode the drawing');
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
