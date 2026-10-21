import 'dart:ui' show Locale;

import 'package:cutter/app/app.dart';
import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('boots into the editor with its localized title', (tester) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale('en');
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);

    final database = AppDatabase.inMemory();
    addTearDown(() => tester.runAsync(database.close));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const CutterApp(),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.text('Editor').first);
    final localizations = AppLocalizations.of(context)!;

    expect(localizations.localeName, 'en');
    expect(localizations.editorTitle, 'Editor');
  });
}
