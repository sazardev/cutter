import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/project_summary.dart';
import 'package:cutter/features/editor/domain/template.dart';
import 'package:cutter/features/editor/presentation/editor_page.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/home/domain/home_preferences.dart';
import 'package:cutter/features/home/domain/project_list_query.dart';
import 'package:cutter/features/home/presentation/home_providers.dart';
import 'package:cutter/features/home/presentation/new_project/new_project_page.dart';
import 'package:cutter/features/home/presentation/project_card.dart';
import 'package:cutter/features/home/presentation/project_toolbar.dart';
import 'package:cutter/features/home/presentation/rename_project_dialog.dart';
import 'package:cutter/features/home/presentation/template_labels.dart';
import 'package:cutter/features/library/presentation/videos_section.dart';
import 'package:cutter/features/onboarding/presentation/onboarding_page.dart';
import 'package:cutter/features/settings/presentation/settings_page.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double _contentMaxWidth = 1200;
const double _emptyMaxWidth = 360;
const double _cardMaxWidth = 420;
const double _cardMinWidth = 400;
const double _listMaxWidth = 720;
const double _cardHeight = 112;
const double _bottomClearance = 96;
const int _pageSize = 12;

/// The home screen: the user's projects with search, filters, sort and pins,
/// a guided way to create one, the rendered videos and the introduction.
class HomePage extends ConsumerWidget {
  /// Creates the home screen.
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final summaries = ref.watch(projectSummariesProvider);
    final hasProjects = summaries.valueOrNull?.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeTitle),
        actions: [
          IconButton(
            tooltip: l10n.settingsAction,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _showSettings(context),
          ),
          IconButton(
            tooltip: l10n.helpAction,
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showIntroduction(context),
          ),
        ],
      ),
      floatingActionButton: hasProjects
          ? FloatingActionButton.extended(
              onPressed: () => _newProject(context, ref),
              icon: const Icon(Icons.add),
              label: Text(l10n.newProjectAction),
            )
          : null,
      body: SafeArea(
        child: summaries.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => _LoadError(
            onRetry: () => ref.invalidate(projectSummariesProvider),
          ),
          data: (projects) => _Content(
            projects: projects,
            onCreate: () => _newProject(context, ref),
            onCreateFromTemplate: (template) =>
                _newProject(context, ref, templateId: template.id),
            onOpen: (id) => _open(context, ref, id),
            onRename: (project) => _rename(context, ref, project),
            onTrash: (project) => _confirmTrash(context, ref, project),
            onDeleteForever: (project) =>
                _confirmDeleteForever(context, ref, project),
          ),
        ),
      ),
    );
  }

  void _showSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const SettingsPage()),
    );
  }

  void _showIntroduction(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => OnboardingPage(
          onFinished: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  /// Opens the guide, creates the project it describes and opens it.
  Future<void> _newProject(
    BuildContext context,
    WidgetRef ref, {
    String? templateId,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final count = ref.read(projectSummariesProvider).valueOrNull?.length ?? 0;
    final request = await Navigator.of(context).push<NewProjectRequest>(
      MaterialPageRoute(
        builder: (context) => NewProjectPage(
          suggestedName: l10n.defaultProjectName(count + 1),
          initialTemplateId: templateId,
        ),
      ),
    );
    if (request == null || !context.mounted) return;
    final result = await ref.read(createProjectProvider).call(
          name: request.name,
          templateId: request.templateId,
          canvas: request.canvas,
        );
    if (!context.mounted) return;
    switch (result) {
      case Ok(:final value):
        await _open(context, ref, value.id);
      // The guide only offers a known template and a non-empty name, so a
      // failure here is not reachable; the user stays on the home screen.
      case Err():
        break;
    }
  }

  /// Asks for a new name and renames [project].
  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    ProjectSummary project,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => RenameProjectDialog(currentName: project.name),
    );
    if (name == null || name == project.name) return;
    await ref
        .read(renameProjectProvider)
        .call(projectId: project.id, name: name);
    ref.invalidate(projectSummariesProvider);
  }

  /// Asks before moving [project] to the trash, where it can be restored
  /// for a week.
  Future<void> _confirmTrash(
    BuildContext context,
    WidgetRef ref,
    ProjectSummary project,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.homeTrashTitle(project.name)),
        content: Text(l10n.homeTrashBody),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.homeTrashAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(homePreferencesProvider.notifier).trash(project.id);
  }

  /// Asks before deleting the trashed [project] for good, naming what is
  /// lost, then deletes it.
  Future<void> _confirmDeleteForever(
    BuildContext context,
    WidgetRef ref,
    ProjectSummary project,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.homeDeleteTitle(project.name)),
        content: Text(l10n.homeDeleteBody(project.clipCount)),
        actions: [
          // Cancel takes the focus: the destructive button is never the
          // default.
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.homeDeleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(homePreferencesProvider.notifier).deleteForever(project.id);
    ref.invalidate(projectSummariesProvider);
  }

  Future<void> _open(BuildContext context, WidgetRef ref, String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => EditorPage(projectId: id),
      ),
    );
    ref
      ..invalidate(projectSummariesProvider)
      ..invalidate(exportRecordsProvider);
  }
}

class _Content extends ConsumerStatefulWidget {
  const _Content({
    required this.projects,
    required this.onCreate,
    required this.onCreateFromTemplate,
    required this.onOpen,
    required this.onRename,
    required this.onTrash,
    required this.onDeleteForever,
  });

  final List<ProjectSummary> projects;
  final VoidCallback onCreate;
  final ValueChanged<Template> onCreateFromTemplate;
  final ValueChanged<String> onOpen;
  final ValueChanged<ProjectSummary> onRename;
  final ValueChanged<ProjectSummary> onTrash;
  final ValueChanged<ProjectSummary> onDeleteForever;

  @override
  ConsumerState<_Content> createState() => _ContentState();
}

class _ContentState extends ConsumerState<_Content> {
  int _visible = _pageSize;
  bool _cleaning = false;

  @override
  Widget build(BuildContext context) {
    final margin = marginFor(windowClassOf(MediaQuery.sizeOf(context).width));
    final query = ref.watch(projectQueryProvider);
    final preferences = ref.watch(homePreferencesProvider);
    // A new search, filter or sort starts again from the first page.
    ref.listen(
      projectQueryProvider,
      (_, __) => setState(() => _visible = _pageSize),
    );
    ref.listen(
      homePreferencesProvider.select((p) => p.sort),
      (_, __) => setState(() => _visible = _pageSize),
    );

    final existingIds = {for (final project in widget.projects) project.id};
    final now = DateTime.now();
    final needsPurge = preferences.expiredTrash(now).isNotEmpty;
    // Pins, archive and trash entries of projects deleted elsewhere (the
    // editor) are forgotten.
    final stale = preferences.pinnedIds.difference(existingIds).isNotEmpty ||
        preferences.archivedIds.difference(existingIds).isNotEmpty ||
        preferences.trashedAtMs.keys.any((id) => !existingIds.contains(id));
    if ((needsPurge || stale) && !_cleaning) {
      _cleaning = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final controller = ref.read(homePreferencesProvider.notifier);
        // The trash empties itself: a project there more than a week goes.
        if (await controller.purgeExpired(DateTime.now())) {
          ref.invalidate(projectSummariesProvider);
        } else {
          await controller.prune(existingIds);
        }
        _cleaning = false;
      });
    }

    final hasProjects = widget.projects.isNotEmpty;
    final matches = applyProjectQuery(
      widget.projects,
      query,
      preferences.sort,
      now: now,
      preferences: preferences,
    );
    // Pinned projects have a section of their own, always shown in full;
    // the rest is paged.
    final pinned = [
      for (final project in matches)
        if (preferences.pinnedIds.contains(project.id)) project,
    ];
    final others = [
      for (final project in matches)
        if (!preferences.pinnedIds.contains(project.id)) project,
    ];
    final shown = others.take(_visible).toList();

    final l10n = AppLocalizations.of(context)!;
    final controller = ref.read(homePreferencesProvider.notifier);
    final scope = query.scope;

    List<ProjectAction> actionsFor(ProjectSummary project) => switch (scope) {
          ProjectScope.active || ProjectScope.archived => [
              ProjectAction(
                icon: Icons.drive_file_rename_outline,
                label: l10n.renameAction,
                onTap: () => widget.onRename(project),
              ),
              if (scope == ProjectScope.active)
                ProjectAction(
                  icon: Icons.archive_outlined,
                  label: l10n.homeArchiveAction,
                  onTap: () => controller.archive(project.id),
                )
              else
                ProjectAction(
                  icon: Icons.unarchive_outlined,
                  label: l10n.homeUnarchiveAction,
                  onTap: () => controller.unarchive(project.id),
                ),
              ProjectAction(
                icon: Icons.delete_outline,
                label: l10n.homeTrashAction,
                destructive: true,
                onTap: () => widget.onTrash(project),
              ),
            ],
          ProjectScope.trash => [
              ProjectAction(
                icon: Icons.restore_from_trash_outlined,
                label: l10n.homeRestoreAction,
                onTap: () => controller.restore(project.id),
              ),
              ProjectAction(
                icon: Icons.delete_forever_outlined,
                label: l10n.homeDeleteNowAction,
                destructive: true,
                onTap: () => widget.onDeleteForever(project),
              ),
            ],
        };

    Widget card(ProjectSummary project) => ProjectCard(
          project: project,
          pinned: preferences.pinnedIds.contains(project.id),
          actions: actionsFor(project),
          statusLine: scope == ProjectScope.trash
              ? l10n.homeTrashDaysLeft(preferences.daysLeft(project.id, now))
              : null,
          onOpen: scope == ProjectScope.trash
              ? null
              : () => widget.onOpen(project.id),
          onTogglePin: scope == ProjectScope.active
              ? () => controller.togglePin(project.id)
              : null,
        );

    // Portrait and square windows list one project per row, so the name
    // always has room; only landscape windows use a grid, with cards never
    // narrower than _cardMinWidth.
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;

    SliverPadding grid(List<ProjectSummary> items) => SliverPadding(
          padding: EdgeInsets.fromLTRB(margin, AppSpacing.md, margin, 0),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              final columns = landscape
                  ? ((constraints.crossAxisExtent + AppSpacing.md) ~/
                          (_cardMinWidth + AppSpacing.md))
                      .clamp(1, 4)
                  : 1;
              return SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: _cardHeight,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) => card(items[index]),
              );
            },
          ),
        );

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: landscape ? _contentMaxWidth : _listMaxWidth,
        ),
        child: CustomScrollView(
          slivers: [
            if (!hasProjects)
              SliverPadding(
                padding: EdgeInsets.all(margin),
                sliver: SliverToBoxAdapter(
                  child: _EmptyProjects(
                    onCreate: widget.onCreate,
                    onCreateFromTemplate: widget.onCreateFromTemplate,
                  ),
                ),
              )
            else ...[
              SliverPadding(
                padding: EdgeInsets.fromLTRB(margin, margin, margin, 0),
                sliver: SliverToBoxAdapter(
                  child: ProjectToolbar(projects: widget.projects),
                ),
              ),
              if (matches.isEmpty)
                SliverPadding(
                  padding: EdgeInsets.all(margin),
                  sliver: SliverToBoxAdapter(
                    // An empty main list with nothing typed is the first-use
                    // state, with the way to create a project.
                    child: scope == ProjectScope.active && !query.isActive
                        ? _EmptyProjects(
                            onCreate: widget.onCreate,
                            onCreateFromTemplate: widget.onCreateFromTemplate,
                            showTemplates: false,
                          )
                        : _NoResults(query: query),
                  ),
                ),
              if (scope == ProjectScope.trash && others.isNotEmpty)
                SliverPadding(
                  padding:
                      EdgeInsets.fromLTRB(margin, AppSpacing.lg, margin, 0),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      l10n.homeTrashNotice,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ),
              if (pinned.isNotEmpty) ...[
                _sectionHeader(
                  context,
                  margin,
                  Icons.push_pin,
                  l10n.homePinnedSection,
                  pinned.length,
                ),
                grid(pinned),
              ],
              if (others.isNotEmpty) ...[
                _sectionHeader(
                  context,
                  margin,
                  switch (scope) {
                    ProjectScope.active => Icons.movie_outlined,
                    ProjectScope.archived => Icons.archive_outlined,
                    ProjectScope.trash => Icons.delete_outline,
                  },
                  switch (scope) {
                    ProjectScope.active => l10n.homeProjectsSection,
                    ProjectScope.archived => l10n.homeScopeArchived,
                    ProjectScope.trash => l10n.homeScopeTrash,
                  },
                  others.length,
                ),
                grid(shown),
              ],
              if (others.length > shown.length)
                SliverToBoxAdapter(
                  child: _ShowMore(
                    shown: shown.length,
                    total: others.length,
                    onMore: () => setState(() => _visible += _pageSize),
                  ),
                ),
            ],
            if (scope == ProjectScope.active)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: margin),
                sliver: const SliverToBoxAdapter(child: VideosSection()),
              ),
            // Keeps the last card clear of the extended action button.
            const SliverToBoxAdapter(child: SizedBox(height: _bottomClearance)),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context,
    double margin,
    IconData icon,
    String title,
    int count,
  ) {
    final theme = Theme.of(context);
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(margin, AppSpacing.xl, margin, 0),
      sliver: SliverToBoxAdapter(
        child: Semantics(
          header: true,
          child: Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '$count',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final _templatesProvider = FutureProvider<List<Template>>(
  (ref) => ref.watch(templateCatalogProvider).all(),
);

/// The first-use state: a hero with the one action and the templates as a
/// shortcut. Once there is any project it never shows again.
class _EmptyProjects extends ConsumerWidget {
  const _EmptyProjects({
    required this.onCreate,
    required this.onCreateFromTemplate,
    this.showTemplates = true,
  });

  final VoidCallback onCreate;
  final ValueChanged<Template> onCreateFromTemplate;

  /// Whether the templates are offered; off once the user has projects.
  final bool showTemplates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final templates = showTemplates
        ? ref.watch(_templatesProvider).valueOrNull ?? const []
        : const <Template>[];
    return Column(
      children: [
        Card(
          margin: EdgeInsets.zero,
          color: scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _emptyMaxWidth),
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    children: [
                      Icon(
                        Icons.movie_edit,
                        size: AppSpacing.max,
                        color: scheme.onPrimaryContainer,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        l10n.homeEmptyTitle,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        l10n.homeEmptyBody,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      FilledButton.icon(
                        onPressed: onCreate,
                        icon: const Icon(Icons.add),
                        label: Text(l10n.newProjectAction),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (templates.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              l10n.templatesTitle,
              style: theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              l10n.templatesBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              for (final template in templates)
                _TemplateCard(
                  template: template,
                  onTap: () => onCreateFromTemplate(template),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.onTap});

  final Template template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final labels = templateLabels(l10n, template);
    return SizedBox(
      width: _cardMaxWidth - AppSpacing.giant,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(labels.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  labels.body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoResults extends ConsumerWidget {
  const _NoResults({required this.query});

  final ProjectListQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final text = query.text.trim();
    final plain = !query.copyWith(scope: ProjectScope.active).isActive;
    final (title, body) = switch (query.scope) {
      ProjectScope.trash when plain => (
          l10n.homeTrashEmptyTitle,
          l10n.homeTrashEmptyBody,
        ),
      ProjectScope.archived when plain => (
          l10n.homeArchivedEmptyTitle,
          l10n.homeArchivedEmptyBody,
        ),
      _ => (
          l10n.homeNoResultsTitle,
          text.isEmpty
              ? l10n.homeNoResultsFilters
              : l10n.homeNoResultsFor(text),
        ),
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _emptyMaxWidth),
        child: Semantics(
          liveRegion: true,
          child: Column(
            children: [
              Icon(
                Icons.search_off,
                size: AppSpacing.giant,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton(
                onPressed: () => ref.read(projectQueryProvider.notifier).state =
                    const ProjectListQuery(),
                child: Text(l10n.homeClearFilters),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShowMore extends StatelessWidget {
  const _ShowMore({
    required this.shown,
    required this.total,
    required this.onMore,
  });

  final int shown;
  final int total;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          Text(
            l10n.homeShowing(shown, total),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(onPressed: onMore, child: Text(l10n.homeShowMore)),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _emptyMaxWidth),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.loadErrorTitle,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.loadErrorBody,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(onPressed: onRetry, child: Text(l10n.retryAction)),
            ],
          ),
        ),
      ),
    );
  }
}
