import 'package:cutter/features/editor/domain/project_summary.dart';
import 'package:cutter/features/home/domain/home_preferences.dart';
import 'package:cutter/features/home/domain/project_list_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 21, 12);

  test('togglePin pins and unpins', () {
    const empty = HomePreferences();
    final pinned = empty.togglePin('a');
    expect(pinned.pinnedIds, {'a'});
    expect(pinned.togglePin('a').pinnedIds, isEmpty);
  });

  test('archiving and trashing unpin; trashing also unarchives', () {
    final prefs = const HomePreferences(pinnedIds: {'a', 'b'}).archive('a');
    expect(prefs.pinnedIds, {'b'});
    expect(prefs.archivedIds, {'a'});

    final trashed = prefs.trash('a', 5);
    expect(trashed.archivedIds, isEmpty);
    expect(trashed.trashedAtMs, {'a': 5});
    expect(trashed.restore('a').trashedAtMs, isEmpty);
    expect(prefs.unarchive('a').archivedIds, isEmpty);
  });

  test('the trash expires after seven days and counts the days left', () {
    final eightDaysAgo =
        now.subtract(const Duration(days: 8)).millisecondsSinceEpoch;
    final twoDaysAgo =
        now.subtract(const Duration(days: 2)).millisecondsSinceEpoch;
    final prefs = HomePreferences(
      trashedAtMs: {'old': eightDaysAgo, 'new': twoDaysAgo},
    );

    expect(prefs.expiredTrash(now), {'old'});
    expect(prefs.daysLeft('new', now), 5);
    expect(prefs.daysLeft('old', now), 0);
    expect(prefs.daysLeft('missing', now), 0);
  });

  test('each library scope lists only its projects', () {
    ProjectSummary p(String id) => ProjectSummary(
          id: id,
          name: id,
          layerCount: 0,
          clipCount: 0,
          durationMs: 0,
          updatedAtMs: 0,
        );
    final projects = [p('a'), p('b'), p('c')];
    final prefs = const HomePreferences().archive('b').trash('c', 1);

    List<String> ids(ProjectScope scope) => [
          for (final project in applyProjectQuery(
            projects,
            ProjectListQuery(scope: scope),
            ProjectSort.name,
            now: now,
            preferences: prefs,
          ))
            project.id,
        ];

    expect(ids(ProjectScope.active), ['a']);
    expect(ids(ProjectScope.archived), ['b']);
    expect(ids(ProjectScope.trash), ['c']);
    expect(
      const ProjectListQuery(scope: ProjectScope.trash).hasFilters,
      isTrue,
    );
  });
}
