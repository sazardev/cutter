import 'dart:math' as math;

import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/app/theme/seed_presets.dart';
import 'package:cutter/features/settings/domain/appearance_settings.dart';
import 'package:cutter/features/settings/presentation/appearance_providers.dart';
import 'package:cutter/features/settings/presentation/settings_widgets.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double _swatchSize = 48;
const double _swatchGap = 8;
const double _customSaturation = 0.65;
const double _customValue = 0.8;
const int _textScaleSteps = 12;
const int _radiusSteps = 6;

/// Theme, color, corners and text size: every change repaints the app at
/// once and is kept between launches.
class AppearanceSection extends ConsumerWidget {
  /// Creates the section.
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(appearanceProvider);
    final controller = ref.read(appearanceProvider.notifier);
    return Column(
      children: [
        SettingsGroup(
          children: [
            _ThemeModeRow(settings: settings, controller: controller),
            _ColorRow(settings: settings, controller: controller),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        SettingsGroup(
          children: [
            _CornersRow(settings: settings, controller: controller),
            _TextSizeRow(settings: settings, controller: controller),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        SettingsGroup(
          children: [
            SettingsTile(
              icon: Icons.restart_alt,
              title: l10n.settingsResetAction,
              onTap: settings.isDefault ? null : controller.reset,
            ),
          ],
        ),
      ],
    );
  }
}

class _ThemeModeRow extends StatelessWidget {
  const _ThemeModeRow({required this.settings, required this.controller});

  final AppearanceSettings settings;
  final AppearanceController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SettingsBlock(
      title: l10n.settingsThemeModeTitle,
      help: l10n.settingsThemeModeHelp,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<AppThemeMode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: AppThemeMode.system,
                icon: const Icon(Icons.brightness_auto),
                label: Text(l10n.themeModeSystem),
              ),
              ButtonSegment(
                value: AppThemeMode.light,
                icon: const Icon(Icons.light_mode),
                label: Text(l10n.themeModeLight),
              ),
              ButtonSegment(
                value: AppThemeMode.dark,
                icon: const Icon(Icons.dark_mode),
                label: Text(l10n.themeModeDark),
              ),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (selection) => controller.update(
              (current) => current.copyWith(themeMode: selection.first),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorRow extends ConsumerWidget {
  const _ColorRow({required this.settings, required this.controller});

  final AppearanceSettings settings;
  final AppearanceController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // Until the platform answers, assume the palette is there so the option
    // does not flicker on devices that have it.
    final dynamicAvailable =
        ref.watch(dynamicColorAvailableProvider).valueOrNull ?? true;
    final source = settings.colorSource;

    return SettingsBlock(
      title: l10n.settingsColorTitle,
      help: l10n.settingsColorHelp,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<ColorSource>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: ColorSource.dynamic,
                enabled: dynamicAvailable,
                icon: const Icon(Icons.wallpaper),
                label: Text(l10n.colorSourceDynamic),
              ),
              ButtonSegment(
                value: ColorSource.preset,
                icon: const Icon(Icons.palette_outlined),
                label: Text(l10n.colorSourcePreset),
              ),
              ButtonSegment(
                value: ColorSource.custom,
                icon: const Icon(Icons.tune),
                label: Text(l10n.colorSourceCustom),
              ),
            ],
            selected: {source},
            onSelectionChanged: (selection) => controller.update(
              (current) => current.copyWith(colorSource: selection.first),
            ),
          ),
          if (!dynamicAvailable) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.settingsDynamicUnavailable,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (source == ColorSource.preset) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: _swatchGap,
              runSpacing: _swatchGap,
              children: [
                for (final preset in SeedPreset.all)
                  _Swatch(
                    color: preset.color,
                    label: _presetName(l10n, preset.id),
                    selected: settings.presetId == preset.id,
                    onTap: () => controller.update(
                      (current) => current.copyWith(presetId: preset.id),
                    ),
                  ),
              ],
            ),
          ],
          if (source == ColorSource.custom) ...[
            const SizedBox(height: AppSpacing.sm),
            _HueSlider(settings: settings, controller: controller),
          ],
        ],
      ),
    );
  }

  String _presetName(AppLocalizations l10n, String id) {
    switch (id) {
      case 'blue':
        return l10n.colorBlue;
      case 'teal':
        return l10n.colorTeal;
      case 'green':
        return l10n.colorGreen;
      case 'orange':
        return l10n.colorOrange;
      case 'red':
        return l10n.colorRed;
      case 'pink':
        return l10n.colorPink;
      default:
        return l10n.colorViolet;
    }
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : Colors.black;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: onTap,
          radius: _swatchSize / 2,
          child: Container(
            width: _swatchSize,
            height: _swatchSize,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: selected ? Icon(Icons.check, color: onColor) : null,
          ),
        ),
      ),
    );
  }
}

class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.settings, required this.controller});

  final AppearanceSettings settings;
  final AppearanceController controller;

  int _seedFor(double hue) => HSVColor.fromAHSV(
        1,
        hue,
        _customSaturation,
        _customValue,
      ).toColor().toARGB32();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hue = HSVColor.fromColor(Color(settings.customSeed)).hue;
    return Row(
      children: [
        Container(
          width: _swatchSize,
          height: _swatchSize,
          decoration: BoxDecoration(
            color: Color(settings.customSeed),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Semantics(
            label: l10n.settingsCustomColorLabel,
            child: Slider(
              value: hue.clamp(0, 360),
              max: 360,
              onChanged: (value) => controller.preview(
                (current) => current.copyWith(customSeed: _seedFor(value)),
              ),
              onChangeEnd: (_) => controller.commit(),
            ),
          ),
        ),
      ],
    );
  }
}

class _CornersRow extends StatelessWidget {
  const _CornersRow({required this.settings, required this.controller});

  final AppearanceSettings settings;
  final AppearanceController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final radius = settings.customRadius.round();
    return SettingsBlock(
      title: l10n.settingsCornersTitle,
      help: l10n.settingsCornersHelp,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<CornerStyle>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: CornerStyle.clean,
                icon: const Icon(Icons.crop_square),
                label: Text(l10n.cornerStyleClean),
              ),
              ButtonSegment(
                value: CornerStyle.consistent,
                icon: const Icon(Icons.rounded_corner),
                label: Text(l10n.cornerStyleConsistent),
              ),
              ButtonSegment(
                value: CornerStyle.custom,
                icon: const Icon(Icons.tune),
                label: Text(l10n.cornerStyleCustom),
              ),
            ],
            selected: {settings.cornerStyle},
            onSelectionChanged: (selection) => controller.update(
              (current) => current.copyWith(cornerStyle: selection.first),
            ),
          ),
          if (settings.cornerStyle == CornerStyle.custom) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(l10n.settingsCornerRadiusLabel(radius)),
            Slider(
              value: settings.customRadius,
              max: AppearanceSettings.maxCustomRadius,
              divisions: _radiusSteps * 2,
              label: l10n.settingsCornerRadiusLabel(radius),
              onChanged: (value) => controller.preview(
                (current) => current.copyWith(customRadius: value),
              ),
              onChangeEnd: (_) => controller.commit(),
            ),
          ],
        ],
      ),
    );
  }
}

class _TextSizeRow extends StatelessWidget {
  const _TextSizeRow({required this.settings, required this.controller});

  final AppearanceSettings settings;
  final AppearanceController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final percent = (settings.textScale * 100).round();
    return SettingsBlock(
      title: l10n.settingsTextTitle,
      help: l10n.settingsTextHelp,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.settingsTextScaleLabel(percent)),
          Slider(
            value: settings.textScale,
            min: AppearanceSettings.minTextScale,
            max: AppearanceSettings.maxTextScale,
            divisions: _textScaleSteps,
            label: '$percent%',
            semanticFormatterCallback: (value) =>
                l10n.settingsTextScaleLabel(math.max(0, (value * 100).round())),
            onChanged: (value) => controller.preview(
              (current) => current.copyWith(textScale: value),
            ),
            onChangeEnd: (_) => controller.commit(),
          ),
        ],
      ),
    );
  }
}
