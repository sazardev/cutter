import 'package:cutter/features/onboarding/presentation/onboarding_page.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  Locale locale,
  VoidCallback onFinished,
) {
  return tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: OnboardingPage(onFinished: onFinished),
    ),
  );
}

void main() {
  for (final locale in const [Locale('en'), Locale('es')]) {
    final tag = locale.languageCode;

    testWidgets('walks the three pages and finishes ($tag)', (tester) async {
      final l10n = await AppLocalizations.delegate.load(locale);
      var finished = 0;
      await _pump(tester, locale, () => finished++);

      expect(find.text(l10n.onboardingLayersTitle), findsOneWidget);
      expect(find.text(l10n.onboardingSkip), findsOneWidget);

      await tester.tap(find.text(l10n.onboardingNext));
      await tester.pumpAndSettle();
      expect(find.text(l10n.onboardingCutTitle), findsOneWidget);

      await tester.tap(find.text(l10n.onboardingNext));
      await tester.pumpAndSettle();
      expect(find.text(l10n.onboardingTuneTitle), findsOneWidget);
      expect(find.text(l10n.onboardingSkip), findsNothing);
      expect(finished, 0);

      await tester.tap(find.text(l10n.onboardingStart));
      expect(finished, 1);
    });

    testWidgets('skip finishes at once ($tag)', (tester) async {
      final l10n = await AppLocalizations.delegate.load(locale);
      var finished = 0;
      await _pump(tester, locale, () => finished++);

      await tester.tap(find.text(l10n.onboardingSkip));

      expect(finished, 1);
    });
  }
}
