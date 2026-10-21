import 'package:cutter/app/brand/brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keeps the 9:7 ratio of the artwork and hides from semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: BrandMark(size: 90))),
    );

    final size = tester.getSize(find.byType(BrandMark));
    expect(size.width, 90);
    expect(size.height, 70);
    expect(find.byType(ExcludeSemantics), findsWidgets);
  });
}
