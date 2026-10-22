import 'dart:convert';

import 'package:cutter/features/editor/domain/clip_drawing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const stroke = DrawingStroke(
    color: 0xFFE53935,
    width: 0.02,
    points: [0.1, 0.2, 0.3, 0.4],
  );

  test('a drawing survives a trip through JSON', () {
    const drawing = ClipDrawing([
      stroke,
      DrawingStroke(color: 0, width: 0.05, erase: true, points: [0.5, 0.5]),
    ]);

    final back = ClipDrawing.fromJson(
      jsonDecode(jsonEncode(drawing.toJson())) as Map<String, dynamic>,
    );

    expect(back, drawing);
    expect(back.hashCode, drawing.hashCode);
  });

  test('plus and withoutLast add and take off the top stroke', () {
    final one = ClipDrawing.empty.plus(stroke);

    expect(one.strokes, [stroke]);
    expect(one.withoutLast(), ClipDrawing.empty);
    expect(ClipDrawing.empty.withoutLast(), ClipDrawing.empty);
  });

  test('a drawing of only erasers is blank', () {
    expect(ClipDrawing.empty.isBlank, isTrue);
    expect(
      const ClipDrawing([
        DrawingStroke(color: 0, width: 0.02, erase: true, points: [0, 0]),
      ]).isBlank,
      isTrue,
    );
    expect(ClipDrawing.empty.plus(stroke).isBlank, isFalse);
  });

  test('a stroke counts its points', () {
    expect(stroke.length, 2);
  });
}
