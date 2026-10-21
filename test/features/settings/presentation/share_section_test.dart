import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/settings/domain/share_preferences.dart';
import 'package:cutter/features/settings/presentation/sections/share_section.dart';
import 'package:cutter/features/settings/presentation/share_preferences_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the switches change the preferences and keep them',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(db.close));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SingleChildScrollView(child: ShareSection())),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text(l10n.sharePlatformSnapchat));
    await tester.tap(find.text(l10n.sharePlatformTiktok));
    await tester.tap(find.text(l10n.settingsShareAutoTitle));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    final saved = container.read(sharePreferencesProvider);
    expect(saved.platforms, contains(SharePlatform.snapchat));
    expect(saved.platforms, isNot(contains(SharePlatform.tiktok)));
    expect(saved.openSheetAutomatically, isTrue);
  });
}
