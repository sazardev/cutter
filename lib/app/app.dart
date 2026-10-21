import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/presentation/editor_page.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Root widget of the app: a [MaterialApp] with the light and dark themes
/// built from the DESIGN.md tokens, the generated [AppLocalizations]
/// delegates and locales, opening on the Editor.
class FieldVisitsApp extends StatelessWidget {
  /// Creates the app shell.
  const FieldVisitsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const EditorPage(),
    );
  }
}
