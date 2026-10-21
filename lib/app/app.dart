import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/presentation/editor_page.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The application root: M3 themes that follow the system brightness,
/// localization delegates and the editor as the home screen.
class CutterApp extends StatelessWidget {
  /// Creates the application root.
  const CutterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.editorTitle,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const EditorPage(),
    );
  }
}
