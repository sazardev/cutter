import 'dart:io';

import 'package:cutter/core/engine/media_engine.dart';
import 'package:cutter/features/editor/presentation/media/media_browser_page.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../core/engine/fake_media_engine.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('cutter_browser_');
    for (final name in ['clip.mp4', 'song.mp3', 'photo.jpg', 'notes.txt']) {
      File('${folder.path}/$name').writeAsStringSync('');
    }
    Directory('${folder.path}/Trip').createSync();
  });

  tearDown(() => folder.deleteSync(recursive: true));

  testWidgets(
      'lists folders and media only, filters by kind and returns '
      'the picked files in order', (tester) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    List<String>? result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mediaEngineProvider.overrideWithValue(FakeMediaEngine())],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<List<String>>(
                  MaterialPageRoute(
                    builder: (_) =>
                        MediaBrowserPage(initialFolder: folder.path),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // The folder is read with real file I/O, an entry per turn.
    for (var i = 0; i < 50 && find.text('Trip').evaluate().isEmpty; i++) {
      await _settle(tester);
    }

    expect(find.text('Trip'), findsOneWidget);
    for (final name in ['clip.mp4', 'song.mp3', 'photo.jpg']) {
      expect(find.bySemanticsLabel(name), findsOneWidget, reason: name);
    }
    expect(find.bySemanticsLabel('notes.txt'), findsNothing);

    await tester.tap(find.text(l10n.layerKindAudio));
    await _settle(tester);
    expect(find.bySemanticsLabel('clip.mp4'), findsNothing);
    expect(find.bySemanticsLabel('song.mp3'), findsOneWidget);

    await tester.tap(find.text(l10n.filterAllMedia));
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('song.mp3'));
    await tester.tap(find.bySemanticsLabel('clip.mp4'));
    await tester.pump();
    await tester.tap(find.text(l10n.browserAdd(2)));
    await _settle(tester);

    expect(result, ['${folder.path}/song.mp3', '${folder.path}/clip.mp4']);
  });
}
