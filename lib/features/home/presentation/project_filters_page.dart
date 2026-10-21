import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/editor/domain/project_summary.dart';
import 'package:cutter/features/home/domain/home_preferences.dart';
import 'package:cutter/features/home/domain/project_list_query.dart';
import 'package:cutter/features/home/presentation/home_labels.dart';
import 'package:cutter/features/home/presentation/home_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double _contentMaxWidth = 720;

/// Opens the sort and filter screen over the home list.
Future<void> openProjectFilters(
  BuildContext context,
  List<ProjectSummary> projects,
) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => ProjectFiltersPage(projects: projects),
    ),
  );
}

/// A full-screen modal to sort the project list and narrow it by kind, last
/// edit and length. Every choice applies at once; the footer button closes
/// the screen and says how many projects match.
class ProjectFiltersPage extends ConsumerWidget {
  /// Creates the screen over [projects], which are counted for the footer.
  const ProjectFiltersPage({required this.projects, super.key});

  /// Every stored project.
  final List<ProjectSummary> projects;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final query = ref.watch(projectQueryProvider);
    final preferences = ref.watch(homePreferencesProvider);
    final sort = preferences.sort;
    final margin = marginFor(windowClassOf(MediaQuery.sizeOf(context).width));
    final count = applyProjectQuery(
      projects,
      query,
      sort,
      now: DateTime.now(),
      preferences: preferences,
    ).length;
    int inScope(ProjectScope scope) => applyProjectQuery(
          projects,
          ProjectListQuery(scope: scope),
          sort,
          now: DateTime.now(),
          preferences: preferences,
        ).length;
    void setQuery(ProjectListQuery next) =>
        ref.read(projectQueryProvider.notifier).state = next;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeFilterTitle),
        actions: [
          TextButton(
            onPressed: query.hasFilters || sort != ProjectSort.recent
                ? () {
                    setQuery(query.withoutFilters());
                    ref
                        .read(homePreferencesProvider.notifier)
                        .setSort(ProjectSort.recent);
                  }
                : null,
            child: Text(l10n.homeFilterReset),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                  child: ListView(
                    padding: EdgeInsets.all(margin),
                    children: [
                      _OptionSection<ProjectScope>(
                        title: l10n.homeFilterScopeSection,
                        values: ProjectScope.values,
                        selected: query.scope,
                        label: (scope) => scope == ProjectScope.active
                            ? l10n.scopeLabel(scope)
                            : l10n.homeScopeCount(
                                l10n.scopeLabel(scope),
                                inScope(scope),
                              ),
                        onSelected: (value) =>
                            setQuery(query.copyWith(scope: value)),
                      ),
                      _OptionSection<ProjectSort>(
                        title: l10n.homeFilterSortSection,
                        values: ProjectSort.values,
                        selected: sort,
                        label: l10n.sortLabel,
                        onSelected: (value) => ref
                            .read(homePreferencesProvider.notifier)
                            .setSort(value),
                      ),
                      _OptionSection<ProjectFilter>(
                        title: l10n.homeFilterShowSection,
                        values: ProjectFilter.values,
                        selected: query.filter,
                        label: l10n.filterLabel,
                        onSelected: (value) =>
                            setQuery(query.copyWith(filter: value)),
                      ),
                      _OptionSection<EditedWithin>(
                        title: l10n.homeFilterEditedSection,
                        values: EditedWithin.values,
                        selected: query.edited,
                        label: l10n.editedLabelOf,
                        onSelected: (value) =>
                            setQuery(query.copyWith(edited: value)),
                      ),
                      _OptionSection<LengthRange>(
                        title: l10n.homeFilterLengthSection,
                        values: LengthRange.values,
                        selected: query.length,
                        label: l10n.lengthLabel,
                        onSelected: (value) =>
                            setQuery(query.copyWith(length: value)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Material(
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: margin,
                      vertical: AppSpacing.md,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(l10n.homeFilterShowResults(count)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionSection<T> extends StatelessWidget {
  const _OptionSection({
    required this.title,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  final String title;
  final List<T> values;
  final T selected;
  final String Function(T value) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final value in values)
                ChoiceChip(
                  label: Text(label(value)),
                  selected: value == selected,
                  onSelected: (_) => onSelected(value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
