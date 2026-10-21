import 'dart:ui' show Locale;

import 'package:cutter/app/app.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the editor title', (tester) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale('en');
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);

    await tester.pumpWidget(const FieldVisitsApp());
    await tester.pumpAndSettle();

    expect(find.text('Cutter'), findsWidgets);

    final context = tester.element(find.text('Cutter').first);
    final localizations = AppLocalizations.of(context);

    expect(localizations.localeName, 'en');
    expect(localizations.editorTitle, 'Cutter');
  });
}
