import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/share_video.dart';
import 'package:cutter/features/editor/presentation/tools/share_block.dart';
import 'package:cutter/features/settings/domain/share_preferences.dart';
import 'package:cutter/features/settings/presentation/share_preferences_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester,
  AppDatabase db,
  List<(String, String)> shared, {
  bool supported = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      shareSupportedProvider.overrideWithValue(supported),
      videoSharerProvider.overrideWithValue(
        (path, title) async => shared.add((path, title)),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ShareBlock(path: '/videos/trip.mp4', title: 'Trip'),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  testWidgets(
      'share and the chosen platforms send the video to the system '
      'sheet', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    final shared = <(String, String)>[];
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _pump(tester, db, shared);

    await tester.tap(find.text(l10n.shareVideoAction));
    await tester.tap(find.text(l10n.sharePlatformTiktok));

    expect(
      shared,
      [('/videos/trip.mp4', 'Trip'), ('/videos/trip.mp4', 'Trip')],
    );
    // Defaults: some platforms are on, others are not.
    expect(find.text(l10n.sharePlatformWhatsapp), findsOneWidget);
    expect(find.text(l10n.sharePlatformSnapchat), findsNothing);
  });

  testWidgets('what the user turned off in Settings is not shown',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final container = await _pump(tester, db, []);

    await container.read(sharePreferencesProvider.notifier).update(
          (p) => p.copyWith(
            platforms: {SharePlatform.youtube},
            showCopyPath: false,
            showWatch: false,
          ),
        );
    await tester.pump();

    expect(find.text(l10n.sharePlatformYoutube), findsOneWidget);
    expect(find.text(l10n.sharePlatformTiktok), findsNothing);
    expect(find.text(l10n.copyPathAction), findsNothing);
    expect(find.text(l10n.exportWatchAction), findsNothing);

    await container
        .read(sharePreferencesProvider.notifier)
        .update((p) => p.copyWith(showAfterExport: false));
    await tester.pump();
    expect(find.text(l10n.shareVideoAction), findsNothing);
  });

  testWidgets('where files cannot be shared only the other actions show',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _pump(tester, db, [], supported: false);

    expect(find.text(l10n.shareVideoAction), findsNothing);
    expect(find.text(l10n.copyPathAction), findsOneWidget);
  });
}
