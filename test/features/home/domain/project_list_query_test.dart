import 'package:cutter/features/editor/domain/project_summary.dart';
import 'package:cutter/features/home/domain/home_preferences.dart';
import 'package:cutter/features/home/domain/project_list_query.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 21, 12);
final _dayMs = const Duration(days: 1).inMilliseconds;

ProjectSummary _p(
  String id,
  String name, {
  int clips = 1,
  int durationMs = 1000,
  int? updatedAtMs,
  int? savedAtMs,
}) =>
    ProjectSummary(
      id: id,
      name: name,
      layerCount: 1,
      clipCount: clips,
      durationMs: durationMs,
      updatedAtMs: updatedAtMs ?? _now.millisecondsSinceEpoch,
      savedAtMs: savedAtMs,
    );

void main() {
  final projects = [
    _p(
      'a',
      'Beach trip',
      updatedAtMs: _now.millisecondsSinceEpoch - 10 * _dayMs,
      durationMs: 5000,
    ),
    _p(
      'b',
      'city Walk',
      updatedAtMs: _now.millisecondsSinceEpoch,
      clips: 0,
      savedAtMs: 5,
      durationMs: 0,
    ),
    _p(
      'c',
      'Alps',
      updatedAtMs: _now.millisecondsSinceEpoch - 2 * _dayMs,
      durationMs: 150000,
      savedAtMs: 7,
    ),
  ];

  List<String> run(
    ProjectListQuery query, [
    ProjectSort sort = ProjectSort.recent,
  ]) =>
      [
        for (final p in applyProjectQuery(projects, query, sort, now: _now))
          p.id,
      ];

  test('sorts by recent, oldest, name, longest or shortest', () {
    const query = ProjectListQuery();
    expect(run(query), ['b', 'c', 'a']);
    expect(run(query, ProjectSort.oldest), ['a', 'c', 'b']);
    expect(run(query, ProjectSort.name), ['c', 'a', 'b']);
    expect(run(query, ProjectSort.longest), ['c', 'a', 'b']);
    expect(run(query, ProjectSort.shortest), ['b', 'a', 'c']);
  });

  test('searches the name ignoring case', () {
    expect(run(const ProjectListQuery(text: ' WALK ')), ['b']);
  });

  test('filters by kind', () {
    expect(
      run(const ProjectListQuery(filter: ProjectFilter.saved)),
      ['b', 'c'],
    );
    expect(run(const ProjectListQuery(filter: ProjectFilter.empty)), ['b']);
  });

  test('filters by how recently it was edited', () {
    expect(run(const ProjectListQuery(edited: EditedWithin.today)), ['b']);
    expect(
      run(const ProjectListQuery(edited: EditedWithin.week)),
      ['b', 'c'],
    );
    expect(
      run(const ProjectListQuery(edited: EditedWithin.month)),
      ['b', 'c', 'a'],
    );
  });

  test('filters by length', () {
    expect(run(const ProjectListQuery(length: LengthRange.short)), ['b', 'a']);
    expect(run(const ProjectListQuery(length: LengthRange.long)), ['c']);
    expect(run(const ProjectListQuery(length: LengthRange.medium)), isEmpty);
  });

  test('isActive and hasFilters tell what narrows the list', () {
    expect(const ProjectListQuery().isActive, isFalse);
    expect(const ProjectListQuery(text: 'x').isActive, isTrue);
    expect(const ProjectListQuery(text: 'x').hasFilters, isFalse);
    expect(const ProjectListQuery(length: LengthRange.long).hasFilters, isTrue);
    expect(
      const ProjectListQuery(text: 'x', edited: EditedWithin.week)
          .withoutFilters()
          .text,
      'x',
    );
  });
}
