import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/editor/domain/project_summary.dart';
import 'package:cutter/features/home/domain/home_preferences.dart';
import 'package:cutter/features/home/domain/project_list_query.dart';
import 'package:cutter/features/home/presentation/home_labels.dart';
import 'package:cutter/features/home/presentation/home_providers.dart';
import 'package:cutter/features/home/presentation/project_filters_page.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double _searchMaxWidth = 640;
const double _searchHeight = 56;
const int _maxSuggestions = 5;

/// The centered search field with name suggestions, the button that opens
/// the sort and filter screen, and a row of chips for what is applied.
class ProjectToolbar extends ConsumerStatefulWidget {
  /// Creates the toolbar over [projects], which feed the suggestions and the
  /// result count of the filter screen.
  const ProjectToolbar({required this.projects, super.key});

  /// Every stored project.
  final List<ProjectSummary> projects;

  @override
  ConsumerState<ProjectToolbar> createState() => _ProjectToolbarState();
}

class _ProjectToolbarState extends ConsumerState<ProjectToolbar> {
  final _search = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setQuery(ProjectListQuery Function(ProjectListQuery q) change) {
    final notifier = ref.read(projectQueryProvider.notifier);
    notifier.state = change(notifier.state);
  }

  Iterable<String> _suggestions(TextEditingValue value) {
    final needle = value.text.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    final seen = <String>{};
    return [
      for (final project in widget.projects)
        if (project.name.toLowerCase().contains(needle) &&
            project.name.toLowerCase() != needle &&
            seen.add(project.name))
          project.name,
    ].take(_maxSuggestions);
  }

  /// The corner shape of the buttons, so the field follows the corner style
  /// chosen in Settings (a pill, or the radius picked there).
  OutlinedBorder _fieldShape(BuildContext context) {
    final theme = Theme.of(context);
    final shape = theme.filledButtonTheme.style?.shape?.resolve({});
    return shape is OutlinedBorder ? shape : const StadiumBorder();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final query = ref.watch(projectQueryProvider);
    final sort = ref.watch(homePreferencesProvider.select((p) => p.sort));
    final shape = _fieldShape(context);
    final activeCount = (query.filter != ProjectFilter.all ? 1 : 0) +
        (query.edited != EditedWithin.any ? 1 : 0) +
        (query.length != LengthRange.any ? 1 : 0) +
        (query.scope != ProjectScope.active ? 1 : 0) +
        (sort != ProjectSort.recent ? 1 : 0);

    // "Clear filters" elsewhere empties the field too.
    ref.listen(projectQueryProvider.select((q) => q.text), (_, text) {
      if (_search.text != text) _search.text = text;
    });

    return Column(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _searchMaxWidth),
            child: Row(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => RawAutocomplete<String>(
                      textEditingController: _search,
                      focusNode: _focus,
                      optionsBuilder: _suggestions,
                      onSelected: (name) =>
                          _setQuery((q) => q.copyWith(text: name)),
                      fieldViewBuilder:
                          (context, controller, focusNode, onSubmitted) =>
                              SearchBar(
                        controller: controller,
                        focusNode: focusNode,
                        hintText: l10n.homeSearchHint,
                        leading: const Icon(Icons.search),
                        elevation: const WidgetStatePropertyAll(0),
                        shape: WidgetStatePropertyAll(shape),
                        constraints:
                            const BoxConstraints(minHeight: _searchHeight),
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        ),
                        onChanged: (text) =>
                            _setQuery((q) => q.copyWith(text: text)),
                        onSubmitted: (_) => onSubmitted(),
                        trailing: [
                          if (query.text.isNotEmpty)
                            IconButton(
                              tooltip: l10n.homeClearSearch,
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  _setQuery((q) => q.copyWith(text: '')),
                            ),
                        ],
                      ),
                      optionsViewBuilder: (context, onSelected, options) =>
                          Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Material(
                            elevation: 3,
                            shape: shape is StadiumBorder
                                ? RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppRadii.extraLarge,
                                    ),
                                  )
                                : shape,
                            clipBehavior: Clip.antiAlias,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth,
                              ),
                              child: ListView(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                children: [
                                  for (final name in options)
                                    ListTile(
                                      leading: const Icon(Icons.search),
                                      title: Text(name),
                                      onTap: () => onSelected(name),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                IconButton.filledTonal(
                  tooltip: l10n.homeFilterTitle,
                  onPressed: () => openProjectFilters(context, widget.projects),
                  icon: Badge(
                    isLabelVisible: activeCount > 0,
                    label: Text('$activeCount'),
                    child: const Icon(Icons.tune),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (query.hasFilters) ...[
          const SizedBox(height: AppSpacing.md),
          _ActiveFilters(query: query, onChange: _setQuery),
        ],
      ],
    );
  }
}

/// What is applied, as chips that remove themselves, and one way to clear
/// them all.
class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({required this.query, required this.onChange});

  final ProjectListQuery query;
  final void Function(ProjectListQuery Function(ProjectListQuery q)) onChange;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    Widget chip(
      String label,
      ProjectListQuery Function(ProjectListQuery) reset,
    ) {
      return InputChip(label: Text(label), onDeleted: () => onChange(reset));
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _searchMaxWidth),
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (query.scope != ProjectScope.active)
              chip(
                l10n.scopeLabel(query.scope),
                (q) => q.copyWith(scope: ProjectScope.active),
              ),
            if (query.filter != ProjectFilter.all)
              chip(
                l10n.filterLabel(query.filter),
                (q) => q.copyWith(filter: ProjectFilter.all),
              ),
            if (query.edited != EditedWithin.any)
              chip(
                l10n.editedLabelOf(query.edited),
                (q) => q.copyWith(edited: EditedWithin.any),
              ),
            if (query.length != LengthRange.any)
              chip(
                l10n.lengthLabel(query.length),
                (q) => q.copyWith(length: LengthRange.any),
              ),
            TextButton(
              onPressed: () => onChange((q) => q.withoutFilters()),
              child: Text(l10n.homeClearFilters),
            ),
          ],
        ),
      ),
    );
  }
}
