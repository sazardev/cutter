import 'dart:ui' show Locale;

import 'package:cutter/app/app.dart';
import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/core/engine/media_engine.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'core/engine/fake_media_engine.dart';

void main() {
  testWidgets(
      'boots into the introduction on first launch and then the home screen',
      (tester) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale('en');
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);

    final database = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(database.close));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          mediaEngineProvider.overrideWithValue(FakeMediaEngine()),
        ],
        child: const CutterApp(),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    final localizations = AppLocalizations.of(context)!;

    expect(localizations.localeName, 'en');
    expect(find.text(localizations.onboardingLayersTitle), findsOneWidget);

    await tester.tap(find.text(localizations.onboardingSkip));
    await tester.pumpAndSettle();

    expect(find.text(localizations.homeEmptyTitle), findsOneWidget);
  });
}
