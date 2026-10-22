import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cutter/features/editor/domain/clip_drawing.dart';
import 'package:cutter/features/editor/presentation/drawing/drawing_painter.dart';
import 'package:flutter_test/flutter_test.dart';

const _red = 0xFFFF0000;

/// The RGBA of the pixel at ([x], [y]) in the PNG [bytes].
Future<List<int>> _pixel(List<int> bytes, int x, int y) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
  final image = (await codec.getNextFrame()).image;
  final data = (await image.toByteData())!;
  final i = (y * image.width + x) * 4;
  return [for (var k = 0; k < 4; k++) data.getUint8(i + k)];
}

void main() {
  const line = DrawingStroke(
    color: _red,
    width: 0.1,
    points: [0.1, 0.5, 0.9, 0.5],
  );

  testWidgets('paints red under the stroke and leaves the rest clear',
      (tester) async {
    await tester.runAsync(() async {
      final png = await renderDrawingPng(const ClipDrawing([line]), 100, 100);

      expect(await _pixel(png, 50, 50), [255, 0, 0, 255]);
      expect((await _pixel(png, 50, 10))[3], 0);
      expect((await _pixel(png, 2, 2))[3], 0);
    });
  });

  testWidgets('an eraser rubs out what it crosses', (tester) async {
    await tester.runAsync(() async {
      const eraser = DrawingStroke(
        color: 0,
        width: 0.2,
        erase: true,
        points: [0.5, 0.2, 0.5, 0.8],
      );
      final png = await renderDrawingPng(
        const ClipDrawing([line, eraser]),
        100,
        100,
      );

      expect((await _pixel(png, 50, 50))[3], 0);
      expect(await _pixel(png, 20, 50), [255, 0, 0, 255]);
    });
  });

  testWidgets('a single tap leaves a dot', (tester) async {
    await tester.runAsync(() async {
      const dot = DrawingStroke(color: _red, width: 0.2, points: [0.5, 0.5]);
      final png = await renderDrawingPng(const ClipDrawing([dot]), 100, 100);

      expect((await _pixel(png, 50, 50))[3], 255);
      expect((await _pixel(png, 5, 5))[3], 0);
    });
  });

  testWidgets('a blank drawing is fully transparent', (tester) async {
    await tester.runAsync(() async {
      final png = await renderDrawingPng(ClipDrawing.empty, 20, 20);

      expect((await _pixel(png, 10, 10))[3], 0);
    });
  });
}
