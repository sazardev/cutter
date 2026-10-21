import 'package:cutter/core/engine/media_engine.dart';
import 'package:cutter/features/home/presentation/project_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/engine/fake_media_engine.dart';

void main() {
  Future<void> pump(WidgetTester tester, String? uri) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mediaEngineProvider.overrideWithValue(FakeMediaEngine())],
        child: MaterialApp(
          home: SizedBox(
            width: 88,
            height: 88,
            child: ProjectCover(
              uri: uri,
              ms: 0,
              placeholder: const Text('placeholder'),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('shows the first frame of the source once it is decoded',
      (tester) async {
    await pump(tester, 'file:///media/clip.mp4');

    expect(find.byType(RawImage), findsOneWidget);
    expect(find.text('placeholder'), findsNothing);
  });

  testWidgets('a project without a cover keeps the placeholder',
      (tester) async {
    await pump(tester, null);

    expect(find.byType(RawImage), findsNothing);
    expect(find.text('placeholder'), findsOneWidget);
  });
}
