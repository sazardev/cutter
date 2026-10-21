import 'package:cutter/features/editor/domain/project_summary.dart';
import 'package:cutter/features/home/domain/home_preferences.dart';

/// Which part of the library the list shows.
enum ProjectScope {
  /// Projects that are neither archived nor in the trash.
  active,

  /// Archived projects.
  archived,

  /// Projects waiting in the trash to be deleted.
  trash,
}

/// How recently a project was edited.
enum EditedWithin {
  /// No limit.
  any,

  /// Since the start of today.
  today,

  /// In the last 7 days.
  week,

  /// In the last 30 days.
  month,
}

/// How long a project is.
enum LengthRange {
  /// No limit.
  any,

  /// Under 30 seconds.
  short,

  /// From 30 seconds to 2 minutes.
  medium,

  /// Over 2 minutes.
  long,
}

const _shortMs = 30 * 1000;
const _longMs = 2 * 60 * 1000;

/// What the user typed and picked to narrow the project list.
class ProjectListQuery {
  /// Creates a query; by default it matches every project.
  const ProjectListQuery({
    this.text = '',
    this.filter = ProjectFilter.all,
    this.edited = EditedWithin.any,
    this.length = LengthRange.any,
    this.scope = ProjectScope.active,
  });

  /// Text a project name must contain, ignoring case.
  final String text;

  /// The kind of project to keep.
  final ProjectFilter filter;

  /// How recently the project was edited.
  final EditedWithin edited;

  /// How long the project is.
  final LengthRange length;

  /// Which part of the library is shown.
  final ProjectScope scope;

  /// True when it narrows the list in any way.
  bool get isActive => text.trim().isNotEmpty || hasFilters;

  /// True when any option besides the search text narrows the list.
  bool get hasFilters =>
      filter != ProjectFilter.all ||
      edited != EditedWithin.any ||
      length != LengthRange.any ||
      scope != ProjectScope.active;

  /// A copy with the given fields replaced.
  ProjectListQuery copyWith({
    String? text,
    ProjectFilter? filter,
    EditedWithin? edited,
    LengthRange? length,
    ProjectScope? scope,
  }) =>
      ProjectListQuery(
        text: text ?? this.text,
        filter: filter ?? this.filter,
        edited: edited ?? this.edited,
        length: length ?? this.length,
        scope: scope ?? this.scope,
      );

  /// The same search text with every option back to its default.
  ProjectListQuery withoutFilters() => ProjectListQuery(text: text);
}

/// Keeps the projects that match [query] in the library part it names (using
/// [preferences] for archive and trash), ordered by [sort]; pinning is not
/// considered here (the screen shows pinned projects in their own section).
/// [now] is the clock used for [EditedWithin]. The input list is not
/// changed.
List<ProjectSummary> applyProjectQuery(
  List<ProjectSummary> projects,
  ProjectListQuery query,
  ProjectSort sort, {
  required DateTime now,
  HomePreferences preferences = const HomePreferences(),
}) {
  final needle = query.text.trim().toLowerCase();
  final editedSince = switch (query.edited) {
    EditedWithin.any => null,
    EditedWithin.today =>
      DateTime(now.year, now.month, now.day).millisecondsSinceEpoch,
    EditedWithin.week =>
      now.subtract(const Duration(days: 7)).millisecondsSinceEpoch,
    EditedWithin.month =>
      now.subtract(const Duration(days: 30)).millisecondsSinceEpoch,
  };

  bool inScope(ProjectSummary project) {
    final trashed = preferences.trashedAtMs.containsKey(project.id);
    return switch (query.scope) {
      ProjectScope.trash => trashed,
      ProjectScope.archived =>
        !trashed && preferences.archivedIds.contains(project.id),
      ProjectScope.active =>
        !trashed && !preferences.archivedIds.contains(project.id),
    };
  }

  bool keep(ProjectSummary project) {
    if (!inScope(project)) return false;
    if (needle.isNotEmpty && !project.name.toLowerCase().contains(needle)) {
      return false;
    }
    if (editedSince != null && project.updatedAtMs < editedSince) {
      return false;
    }
    final lengthOk = switch (query.length) {
      LengthRange.any => true,
      LengthRange.short => project.durationMs < _shortMs,
      LengthRange.medium =>
        project.durationMs >= _shortMs && project.durationMs <= _longMs,
      LengthRange.long => project.durationMs > _longMs,
    };
    if (!lengthOk) return false;
    return switch (query.filter) {
      ProjectFilter.all => true,
      ProjectFilter.saved => project.savedAtMs != null,
      ProjectFilter.empty => project.clipCount == 0,
    };
  }

  int order(ProjectSummary a, ProjectSummary b) => switch (sort) {
        ProjectSort.recent => b.updatedAtMs.compareTo(a.updatedAtMs),
        ProjectSort.oldest => a.updatedAtMs.compareTo(b.updatedAtMs),
        ProjectSort.name =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        ProjectSort.longest => b.durationMs.compareTo(a.durationMs),
        ProjectSort.shortest => a.durationMs.compareTo(b.durationMs),
      };

  return projects.where(keep).toList()..sort(order);
}
