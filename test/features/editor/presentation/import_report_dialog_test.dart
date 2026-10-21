import 'package:cutter/features/editor/domain/import_limits.dart';
import 'package:cutter/features/editor/presentation/editor_controller.dart';
import 'package:cutter/features/editor/presentation/import_report_dialog.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _open(WidgetTester tester, ImportOutcome outcome) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showImportReport(context, outcome),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists what was left out and what to know, by file name',
      (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _open(
      tester,
      const ImportOutcome(
        imported: 1,
        rejected: ['/storage/old.avi'],
        issues: [
          ImportIssue('/storage/old.avi', ImportIssueKind.unreadable),
          ImportIssue('/storage/huge.mp4', ImportIssueKind.storageFull),
        ],
        notices: [
          ImportNotice('/storage/big.mov', ImportNoticeKind.highResolution),
        ],
      ),
    );

    expect(find.text(l10n.importReportDone(1)), findsOneWidget);
    expect(find.text('old.avi'), findsOneWidget);
    expect(find.text(l10n.importIssueUnreadable), findsOneWidget);
    expect(find.text(l10n.importIssueStorageFull), findsOneWidget);
    expect(find.text('big.mov'), findsOneWidget);
    expect(find.text(l10n.importNoticeHighResolution), findsOneWidget);

    await tester.tap(find.text(l10n.importReportClose));
    await tester.pumpAndSettle();
    expect(find.text(l10n.importReportTitle), findsNothing);
  });

  testWidgets('an import with nothing to report shows nothing', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _open(tester, const ImportOutcome(imported: 2, rejected: []));

    expect(find.text(l10n.importReportTitle), findsNothing);
  });
}
