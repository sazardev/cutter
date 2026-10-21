import 'dart:async';

import 'package:cutter/features/music/domain/music_install_state.dart';
import 'package:cutter/features/music/presentation/music_library_page.dart';
import 'package:cutter/features/music/presentation/music_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_music_backend.dart';

Future<void> _pump(
  WidgetTester tester,
  FakeStore store,
  List<dynamic>? catalog,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        musicBackendProvider.overrideWith(
          (ref) async => fakeBackend(store, catalog?.cast()),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MusicLibraryPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('offers a pack, installs it and opens its tracks', (
    tester,
  ) async {
    final store = FakeStore();
    await _pump(tester, store, [testPack()]);

    expect(find.text('Epic epic'), findsOneWidget);
    expect(find.textContaining('2 tracks'), findsOneWidget);

    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(find.text('Ready offline'), findsOneWidget);

    await tester.tap(find.text('Epic epic'));
    await tester.pumpAndSettle();
    expect(find.text('Anthem'), findsOneWidget);
    expect(find.textContaining('120 BPM'), findsOneWidget);
    expect(find.byTooltip('Add to timeline'), findsNWidgets(2));
  });

  testWidgets('a download can be paused, resumed and cancelled', (
    tester,
  ) async {
    final store = FakeStore()..gate = Completer<void>();
    await _pump(tester, store, [testPack()]);

    await tester.tap(find.text('Download'));
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byTooltip('Cancel download'), findsOneWidget);
    expect(find.textContaining('keep going'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Paused'), findsOneWidget);
    expect(find.byTooltip('Resume'), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel download'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Download'), findsOneWidget);
    expect(store.discarded, ['epic']);

    store.gate = null;
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(find.text('Ready offline'), findsOneWidget);
  });

  testWidgets('shows why an install failed and offers a retry', (
    tester,
  ) async {
    final store = FakeStore()..failWith = MusicFailure.corrupt;
    await _pump(tester, store, [testPack()]);

    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(find.textContaining('damaged'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('says so when there is no catalog and nothing installed', (
    tester,
  ) async {
    await _pump(tester, FakeStore(), null);

    expect(find.textContaining('not available'), findsOneWidget);
  });
}
