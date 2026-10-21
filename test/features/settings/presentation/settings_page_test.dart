import 'dart:io';

import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/settings/domain/appearance_repository.dart';
import 'package:cutter/features/settings/domain/appearance_settings.dart';
import 'package:cutter/features/settings/domain/changelog.dart';
import 'package:cutter/features/settings/domain/export_preferences.dart';
import 'package:cutter/features/settings/domain/export_preferences_repository.dart';
import 'package:cutter/features/settings/presentation/app_info_providers.dart';
import 'package:cutter/features/settings/presentation/appearance_providers.dart';
import 'package:cutter/features/settings/presentation/export_preferences_providers.dart';
import 'package:cutter/features/settings/presentation/settings_page.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryRepository implements AppearanceRepository {
  AppearanceSettings? saved;

  @override
  Future<AppearanceSettings> load() async =>
      saved ?? const AppearanceSettings();

  @override
  Future<void> save(AppearanceSettings settings) async => saved = settings;
}

class _MemoryExportRepository implements ExportPreferencesRepository {
  ExportPreferences? saved;

  @override
  Future<ExportPreferences> load() async => saved ?? const ExportPreferences();

  @override
  Future<void> save(ExportPreferences preferences) async => saved = preferences;
}

void main() {
  late _MemoryRepository repository;
  late ProviderContainer container;

  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(1200, 3000),
  }) async {
    // Tall enough that the lazy list builds every row.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repository = _MemoryRepository();
    container = ProviderContainer(
      overrides: [
        appearanceRepositoryProvider.overrideWithValue(repository),
        dynamicColorAvailableProvider.overrideWith((ref) async => true),
        exportPreferencesRepositoryProvider
            .overrideWithValue(_MemoryExportRepository()),
        appVersionProvider
            .overrideWith((ref) async => const AppVersion('1.2.3', '45')),
        changelogProvider.overrideWith(
          (ref) async => [
            const ChangelogRelease('1.2.3', '2026-01-01', [
              ChangelogGroup('Added', ['A shiny thing']),
            ]),
          ],
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
          home: SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('choosing dark mode applies and saves it', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(container.read(appearanceProvider).themeMode, AppThemeMode.dark);
    expect(repository.saved?.themeMode, AppThemeMode.dark);
  });

  testWidgets('custom color and custom corners reveal their sliders',
      (tester) async {
    await pumpPage(tester);
    expect(find.byType(Slider), findsOneWidget); // text size only

    await tester.tap(find.text('Custom').first);
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNWidgets(2));

    await tester.ensureVisible(find.text('Custom').last);
    await tester.tap(find.text('Custom').last);
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNWidgets(3));
  });

  testWidgets('a palette swatch picks the seed and reset restores defaults',
      (tester) async {
    await pumpPage(tester);

    await tester.tap(find.bySemanticsLabel('Teal'));
    await tester.pumpAndSettle();
    expect(container.read(appearanceProvider).presetId, 'teal');

    await tester.ensureVisible(find.text('Reset to defaults'));
    await tester.tap(find.text('Reset to defaults'));
    await tester.pumpAndSettle();
    expect(container.read(appearanceProvider).isDefault, isTrue);
    expect(repository.saved?.isDefault, isTrue);
  });

  testWidgets('dragging the text size previews live and saves on release',
      (tester) async {
    await pumpPage(tester);
    await tester.ensureVisible(find.byType(Slider));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
    );
    await gesture.moveBy(const Offset(200, 0));
    await tester.pump();
    expect(container.read(appearanceProvider).textScale, greaterThan(1));
    expect(repository.saved, isNull);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(repository.saved?.textScale, greaterThan(1));
  });

  testWidgets('on a narrow window the sections open on their own screen',
      (tester) async {
    await pumpPage(tester, size: const Size(400, 900));
    expect(find.text('Dark'), findsNothing);

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();

    expect(find.text('Dark'), findsOneWidget);
  });

  testWidgets('the about section shows the version and opens the changelog',
      (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('1.2.3 (build 45)'), findsOneWidget);

    await tester.tap(find.text('Changelog'));
    await tester.pumpAndSettle();
    expect(find.text('A shiny thing'), findsOneWidget);
    expect(find.text('2026-01-01'), findsOneWidget);
  });

  testWidgets('the export section picks and forgets a folder', (tester) async {
    await pumpPage(tester);
    final dir = Directory.systemTemp.createTempSync('cutter_export_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    container = ProviderContainer(
      overrides: [
        exportPreferencesRepositoryProvider
            .overrideWithValue(_MemoryExportRepository()),
        directoryPickerProvider.overrideWithValue(() async => dir.path),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export').first);
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Choose folder'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(container.read(exportPreferencesProvider).directory, dir.path);

    await tester.tap(find.text('Use default folder'));
    await tester.pumpAndSettle();
    expect(container.read(exportPreferencesProvider).directory, isNull);
  });

  test('the theme follows the color source and the corner style', () {
    final teal = AppTheme.build(
      Brightness.light,
      settings: const AppearanceSettings(presetId: 'teal'),
    );
    expect(
      teal.colorScheme.primary,
      isNot(AppTheme.light().colorScheme.primary),
    );

    const device = ColorScheme.light(primary: Color(0xFF123456));
    final dynamicTheme = AppTheme.build(
      Brightness.light,
      settings: const AppearanceSettings(colorSource: ColorSource.dynamic),
      dynamicScheme: device,
    );
    expect(dynamicTheme.colorScheme.primary, device.primary);

    final ignored = AppTheme.build(
      Brightness.light,
      dynamicScheme: device,
    );
    expect(ignored.colorScheme.primary, AppTheme.light().colorScheme.primary);

    const clean = AppearanceSettings(cornerStyle: CornerStyle.clean);
    expect(
      ShapeScale.of(clean).medium,
      lessThan(ShapeScale.of(const AppearanceSettings()).medium),
    );
    expect(ShapeScale.of(const AppearanceSettings()).pillButtons, isTrue);
  });
}
