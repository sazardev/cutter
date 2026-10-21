import 'package:cutter/features/music/domain/music_ports.dart';
import 'package:cutter/features/music/presentation/music_providers.dart';
import 'package:cutter/features/settings/presentation/sections/music_section.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_music_backend.dart';

Future<FakeStore> _pump(WidgetTester tester, {int installed = 2}) async {
  final store = FakeStore();
  for (final id in ['epic', 'calm'].take(installed)) {
    await store.install(
      testPack(id: id),
      onProgress: (_) {},
      onUnpacking: () {},
      control: TransferControl(),
    );
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        musicBackendProvider.overrideWith(
          (ref) async => fakeBackend(store, [testPack(), testPack(id: 'calm')]),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: MusicSection())),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets('shows what the packs take and lists them', (tester) async {
    await _pump(tester);

    expect(find.textContaining('7.6 MB'), findsWidgets);
    expect(find.textContaining('2 packs'), findsOneWidget);
    expect(find.text('Epic epic'), findsOneWidget);
    expect(find.text('Epic calm'), findsOneWidget);
  });

  testWidgets('removes one pack after confirming', (tester) async {
    final store = await _pump(tester);

    await tester.tap(find.byTooltip('Remove from device').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Remove'), findsWidgets);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(store.packs, hasLength(1));
    expect(find.textContaining('1 pack'), findsOneWidget);
  });

  testWidgets('cancelling the confirmation keeps the pack', (tester) async {
    final store = await _pump(tester);

    await tester.tap(find.byTooltip('Remove from device').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(store.packs, hasLength(2));
  });

  testWidgets('removes every pack at once', (tester) async {
    final store = await _pump(tester);

    await tester.tap(find.text('Remove all packs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(store.packs, isEmpty);
    expect(find.text('No packs downloaded yet.'), findsOneWidget);
  });

  testWidgets('says so when nothing is downloaded', (tester) async {
    await _pump(tester, installed: 0);

    expect(find.text('No packs downloaded yet.'), findsOneWidget);
    expect(find.text('Remove all packs'), findsNothing);
  });
}
