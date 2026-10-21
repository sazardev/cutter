import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/editor/domain/project_summary.dart';
import 'package:cutter/features/editor/presentation/time_format.dart';
import 'package:cutter/features/home/presentation/edited_label.dart';
import 'package:cutter/features/home/presentation/project_cover.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

const double _posterSize = 88;

/// One entry of the menu of a project card.
class ProjectAction {
  /// Creates an action.
  const ProjectAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  /// Leading icon.
  final IconData icon;

  /// What the action does.
  final String label;

  /// Runs the action.
  final VoidCallback onTap;

  /// Whether the action is drawn in the error color.
  final bool destructive;
}

/// A project in the home list: a poster with the first frame and its length,
/// the name, a summary line, a status line, an optional pin button and a menu
/// of actions.
class ProjectCard extends StatelessWidget {
  /// Creates the card of [project].
  const ProjectCard({
    required this.project,
    required this.pinned,
    required this.actions,
    this.statusLine,
    this.onOpen,
    this.onTogglePin,
    super.key,
  });

  /// The project shown.
  final ProjectSummary project;

  /// Whether the project is pinned.
  final bool pinned;

  /// The entries of the card menu.
  final List<ProjectAction> actions;

  /// Replaces the "edited" line, e.g. the days left in the trash.
  final String? statusLine;

  /// Opens the project in the editor; null for a project that cannot be
  /// opened (in the trash).
  final VoidCallback? onOpen;

  /// Pins the project, or unpins it; null hides the pin button.
  final VoidCallback? onTogglePin;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: pinned ? scheme.secondaryContainer : null,
      child: Semantics(
        button: onOpen != null,
        label: l10n.openProjectLabel(project.name),
        excludeSemantics: true,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                _Poster(project: project),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l10n.projectSummary(
                          project.layerCount,
                          formatTimecode(project.durationMs, tenths: true),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        statusLine ??
                            editedLabel(
                              l10n,
                              project.updatedAtMs,
                              DateTime.now(),
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTogglePin != null)
                  IconButton(
                    tooltip: pinned ? l10n.homeUnpinAction : l10n.homePinAction,
                    isSelected: pinned,
                    icon: const Icon(Icons.push_pin_outlined),
                    selectedIcon: const Icon(Icons.push_pin),
                    onPressed: onTogglePin,
                  ),
                PopupMenuButton<void>(
                  tooltip: l10n.homeProjectMenu,
                  itemBuilder: (context) => [
                    for (final action in actions)
                      PopupMenuItem<void>(
                        onTap: action.onTap,
                        child: ListTile(
                          leading: Icon(
                            action.icon,
                            color: action.destructive ? scheme.error : null,
                          ),
                          title: Text(
                            action.label,
                            style: action.destructive
                                ? TextStyle(color: scheme.error)
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.project});

  final ProjectSummary project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.medium),
      child: SizedBox(
        width: _posterSize,
        height: _posterSize,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ProjectCover(
              uri: project.coverUri,
              ms: project.coverMs,
              placeholder: ColoredBox(
                color: scheme.primaryContainer,
                child: Icon(
                  Icons.movie_outlined,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            Positioned(
              right: AppSpacing.xs,
              bottom: AppSpacing.xs,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.scrim.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(AppRadii.extraSmall),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  child: Text(
                    formatTimecode(project.durationMs),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
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
