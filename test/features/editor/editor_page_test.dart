import 'package:cutter/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _compactSize = Size(390, 844);
const _wideSize = Size(900, 700);

Future<void> _pumpApp(
  WidgetTester tester, {
  required Size size,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
  });
  await tester.pumpWidget(const FieldVisitsApp());
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [_compactSize, _wideSize]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'shows title, layers and time at ${size.width} in ${brightness.name}',
        (tester) async {
          await _pumpApp(tester, size: size, brightness: brightness);

          expect(find.text('Cutter'), findsWidgets);
          expect(find.text('Video'), findsWidgets);
          expect(find.text('Image'), findsWidgets);
          expect(find.text('Audio'), findsWidgets);
          expect(find.text('0:00.0 / 0:10.0'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('Play switches to Pause', (tester) async {
    await _pumpApp(tester, size: _compactSize);

    expect(find.text('Play'), findsWidgets);
    await tester.tap(find.text('Play').first);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Pause'), findsWidgets);

    await tester.tap(find.text('Pause').first);
    await tester.pump();
    expect(find.text('Play'), findsWidgets);
  });

  testWidgets('selecting a clip and splitting at the clip start changes '
      'nothing', (tester) async {
    await _pumpApp(tester, size: _wideSize);

    await tester.tap(find.text('Beach.mp4').first);
    await tester.pump();
    await tester.tap(find.text('Split').first, warnIfMissed: false);
    await tester.pump();

    expect(find.text('Beach.mp4'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('choosing the Noir filter shows a check', (tester) async {
    await _pumpApp(tester, size: _wideSize);

    await tester.tap(find.text('Beach.mp4').first);
    await tester.pump();
    await tester.tap(find.text('Filters').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Noir').first);
    await tester.pumpAndSettle();

    expect(find.text('Noir'), findsWidgets);
    expect(find.byIcon(Icons.check), findsWidgets);
  });

  testWidgets('record sheet offers the camera choice without crashing', (
    tester,
  ) async {
    await _pumpApp(tester, size: _wideSize);

    await tester.tap(find.text('Record').first);
    await tester.pumpAndSettle();
    expect(find.text('Camera'), findsWidgets);

    await tester.tap(find.text('Camera').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('exposes semantic labels for the transport controls', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpApp(tester, size: _compactSize);

    expect(find.bySemanticsLabel(RegExp('Play')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('Split')), findsWidgets);
    handle.dispose();
  });
}
