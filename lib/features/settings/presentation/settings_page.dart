import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/settings/presentation/app_info_providers.dart';
import 'package:cutter/features/settings/presentation/sections/about_section.dart';
import 'package:cutter/features/settings/presentation/sections/appearance_section.dart';
import 'package:cutter/features/settings/presentation/sections/export_section.dart';
import 'package:cutter/features/settings/presentation/sections/permissions_section.dart';
import 'package:cutter/features/settings/presentation/sections/share_section.dart';
import 'package:cutter/features/settings/presentation/settings_widgets.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double _wideBreakpoint = 840;
const double _pageMaxWidth = 1160;
const double _navWidth = 320;
const double _detailMaxWidth = 760;
const double _listMaxWidth = 720;

/// The groups of settings.
enum SettingsSection {
  /// Theme, color, corners, text size.
  appearance(Icons.palette_outlined),

  /// Where finished videos are saved.
  export(Icons.ios_share),

  /// What shows after an export, and where to share.
  share(Icons.share_outlined),

  /// What the app may access.
  permissions(Icons.shield_outlined),

  /// Version, changelog, licenses.
  about(Icons.info_outline);

  const SettingsSection(this.icon);

  /// The section's icon.
  final IconData icon;

  /// The section's name.
  String title(AppLocalizations l10n) {
    switch (this) {
      case SettingsSection.appearance:
        return l10n.settingsAppearanceSection;
      case SettingsSection.export:
        return l10n.settingsSectionExport;
      case SettingsSection.share:
        return l10n.settingsSectionShare;
      case SettingsSection.permissions:
        return l10n.settingsSectionPermissions;
      case SettingsSection.about:
        return l10n.settingsSectionAbout;
    }
  }

  /// One line on what the section holds.
  String help(AppLocalizations l10n) {
    switch (this) {
      case SettingsSection.appearance:
        return l10n.settingsSectionAppearanceHelp;
      case SettingsSection.export:
        return l10n.settingsSectionExportHelp;
      case SettingsSection.share:
        return l10n.settingsSectionShareHelp;
      case SettingsSection.permissions:
        return l10n.settingsSectionPermissionsHelp;
      case SettingsSection.about:
        return l10n.settingsSectionAboutHelp;
    }
  }

  /// The section's content.
  Widget get body {
    switch (this) {
      case SettingsSection.appearance:
        return const AppearanceSection();
      case SettingsSection.export:
        return const ExportSection();
      case SettingsSection.share:
        return const ShareSection();
      case SettingsSection.permissions:
        return const PermissionsSection();
      case SettingsSection.about:
        return const AboutSection();
    }
  }
}

/// The settings screen. On wide windows the sections are a column on the
/// left and the chosen one fills the right; on narrow ones it is a list that
/// opens each section on its own screen.
class SettingsPage extends StatefulWidget {
  /// Creates the settings screen.
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SettingsSection _selected = SettingsSection.appearance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;
    final margin = marginFor(windowClassOf(MediaQuery.sizeOf(context).width));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: wide ? _pageMaxWidth : _listMaxWidth,
            ),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: _navWidth,
                        child: _SectionList(
                          margin: margin,
                          selected: _selected,
                          onSelect: (section) =>
                              setState(() => _selected = section),
                        ),
                      ),
                      Expanded(
                        child: _SectionBody(
                          key: ValueKey(_selected),
                          section: _selected,
                          margin: margin,
                          showTitle: true,
                        ),
                      ),
                    ],
                  )
                : _SectionList(
                    margin: margin,
                    onSelect: (section) => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => _SectionScreen(section: section),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The list of sections, each a tile with its icon, name and one line.
class _SectionList extends ConsumerWidget {
  const _SectionList({
    required this.margin,
    required this.onSelect,
    this.selected,
  });

  final double margin;
  final SettingsSection? selected;
  final ValueChanged<SettingsSection> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final version = ref.watch(appVersionProvider).valueOrNull;

    return ListView(
      padding: EdgeInsets.all(margin),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          child: Row(
            children: [
              const SettingsIconBadge(Icons.movie_edit, selected: true),
              const SizedBox(width: AppSpacing.lg),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cutter', style: theme.textTheme.titleLarge),
                  if (version != null)
                    Text(
                      'v${version.version}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        for (final section in SettingsSection.values)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _SectionTile(
              section: section,
              title: section.title(l10n),
              help: section.help(l10n),
              selected: section == selected,
              onTap: () => onSelect(section),
            ),
          ),
      ],
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.section,
    required this.title,
    required this.help,
    required this.selected,
    required this.onTap,
  });

  final SettingsSection section;
  final String title;
  final String help;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color:
            selected ? scheme.secondaryContainer : scheme.surfaceContainerHigh,
        shape: Theme.of(context).cardTheme.shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                SettingsIconBadge(section.icon, selected: selected),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        help,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One section on its own screen, for narrow windows.
class _SectionScreen extends StatelessWidget {
  const _SectionScreen({required this.section});

  final SettingsSection section;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final margin = marginFor(windowClassOf(MediaQuery.sizeOf(context).width));
    return Scaffold(
      appBar: AppBar(title: Text(section.title(l10n))),
      body: SafeArea(
        child: _SectionBody(
          section: section,
          margin: margin,
          showTitle: false,
        ),
      ),
    );
  }
}

class _SectionBody extends StatelessWidget {
  const _SectionBody({
    required this.section,
    required this.margin,
    required this.showTitle,
    super.key,
  });

  final SettingsSection section;
  final double margin;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _detailMaxWidth),
        child: ListView(
          padding: EdgeInsets.all(margin),
          children: [
            if (showTitle) ...[
              Semantics(
                header: true,
                child: Text(
                  section.title(l10n),
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                section.help(l10n),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
            section.body,
          ],
        ),
      ),
    );
  }
}
