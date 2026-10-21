import 'package:cutter/app/brand/brand_mark.dart';
import 'package:cutter/app/brand/brand_splash.dart';
import 'package:cutter/app/theme/seed_presets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('paints the mark on the brand color whatever the app theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData.dark(),
        home: const BrandSplash(),
      ),
    );

    expect(find.byType(BrandMark), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    final expected = ColorScheme.fromSeed(seedColor: SeedPreset.violet.color);
    expect(scaffold.backgroundColor, expected.primary);
  });
}
