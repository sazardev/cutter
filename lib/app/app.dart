import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/home/presentation/home_page.dart';
import 'package:cutter/features/onboarding/presentation/onboarding_page.dart';
import 'package:cutter/features/onboarding/presentation/onboarding_providers.dart';
import 'package:cutter/features/settings/domain/appearance_settings.dart';
import 'package:cutter/features/settings/presentation/appearance_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The application root: M3 themes built from the user's appearance
/// settings, localization delegates and the home screen, preceded by the
/// introduction the first time the app opens.
class CutterApp extends ConsumerWidget {
  /// Creates the application root.
  const CutterApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) => MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context)!.homeTitle,
        theme: AppTheme.build(
          Brightness.light,
          settings: appearance,
          dynamicScheme: lightDynamic,
        ),
        darkTheme: AppTheme.build(
          Brightness.dark,
          settings: appearance,
          dynamicScheme: darkDynamic,
        ),
        themeMode: _themeModeOf(appearance.themeMode),
        builder: (context, child) => _scaleText(
          context,
          child!,
          appearance.textScale,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const _Root(),
      ),
    );
  }

  ThemeMode _themeModeOf(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
    }
  }

  /// Multiplies the font size the system already applies by the user's
  /// factor, so both accessibility settings add up.
  Widget _scaleText(BuildContext context, Widget child, double factor) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        textScaler: TextScaler.linear(media.textScaler.scale(1) * factor),
      ),
      child: child,
    );
  }
}

/// Chooses between the introduction and the home screen.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completed = ref.watch(onboardingCompletedProvider);
    return completed.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      // An unreadable flag must not lock the user out of the app.
      error: (error, stack) => const HomePage(),
      data: (done) {
        if (done) return const HomePage();
        return OnboardingPage(
          onFinished: () async {
            await ref.read(onboardingRepositoryProvider).markCompleted();
            ref.invalidate(onboardingCompletedProvider);
          },
        );
      },
    );
  }
}
