import 'package:flutter/foundation.dart' show immutable, mapEquals, setEquals;

/// How the project list is ordered.
enum ProjectSort {
  /// The most recently edited first.
  recent,

  /// The least recently edited first.
  oldest,

  /// A to Z by name.
  name,

  /// The longest project first.
  longest,

  /// The shortest project first.
  shortest,
}

/// What the home list can show besides everything.
enum ProjectFilter {
  /// Every project.
  all,

  /// Projects with a saved restore point.
  saved,

  /// Projects without any clip yet.
  empty,
}

/// How long a project stays in the trash before it is deleted for good.
const Duration trashRetention = Duration(days: 7);

/// What the user chose for the home list and wants kept between launches.
@immutable
class HomePreferences {
  /// Creates the preferences; the defaults pin, archive and trash nothing
  /// and sort by recent.
  const HomePreferences({
    this.pinnedIds = const {},
    this.archivedIds = const {},
    this.trashedAtMs = const {},
    this.sort = ProjectSort.recent,
  });

  /// Ids of the pinned projects, shown in their own section.
  final Set<String> pinnedIds;

  /// Ids of the archived projects: kept, but out of the main list.
  final Set<String> archivedIds;

  /// The trashed projects by id, with when each was moved there in
  /// milliseconds since the epoch.
  final Map<String, int> trashedAtMs;

  /// The list order.
  final ProjectSort sort;

  /// A copy with the given fields replaced.
  HomePreferences copyWith({
    Set<String>? pinnedIds,
    Set<String>? archivedIds,
    Map<String, int>? trashedAtMs,
    ProjectSort? sort,
  }) {
    return HomePreferences(
      pinnedIds: pinnedIds ?? this.pinnedIds,
      archivedIds: archivedIds ?? this.archivedIds,
      trashedAtMs: trashedAtMs ?? this.trashedAtMs,
      sort: sort ?? this.sort,
    );
  }

  /// A copy with [id] pinned, or unpinned when it already was.
  HomePreferences togglePin(String id) {
    final next = {...pinnedIds};
    if (!next.remove(id)) next.add(id);
    return copyWith(pinnedIds: next);
  }

  /// A copy with [id] archived; it is unpinned.
  HomePreferences archive(String id) => copyWith(
        pinnedIds: {...pinnedIds}..remove(id),
        archivedIds: {...archivedIds, id},
      );

  /// A copy with [id] back in the main list.
  HomePreferences unarchive(String id) =>
      copyWith(archivedIds: {...archivedIds}..remove(id));

  /// A copy with [id] in the trash since [atMs]; it is unpinned and
  /// unarchived.
  HomePreferences trash(String id, int atMs) => copyWith(
        pinnedIds: {...pinnedIds}..remove(id),
        archivedIds: {...archivedIds}..remove(id),
        trashedAtMs: {...trashedAtMs, id: atMs},
      );

  /// A copy with [id] out of the trash.
  HomePreferences restore(String id) =>
      copyWith(trashedAtMs: {...trashedAtMs}..remove(id));

  /// The trashed ids that have been there longer than [trashRetention] at
  /// [now].
  Set<String> expiredTrash(DateTime now) {
    final limit = now.subtract(trashRetention).millisecondsSinceEpoch;
    return {
      for (final entry in trashedAtMs.entries)
        if (entry.value <= limit) entry.key,
    };
  }

  /// When the trashed project [id] is deleted for good, given [now]: whole
  /// days left, at least 1 while it is still there.
  int daysLeft(String id, DateTime now) {
    final since = trashedAtMs[id];
    if (since == null) return 0;
    final left = DateTime.fromMillisecondsSinceEpoch(since)
        .add(trashRetention)
        .difference(now);
    return left.isNegative ? 0 : (left.inHours / 24).ceil().clamp(1, 7);
  }

  @override
  bool operator ==(Object other) =>
      other is HomePreferences &&
      other.sort == sort &&
      setEquals(other.pinnedIds, pinnedIds) &&
      setEquals(other.archivedIds, archivedIds) &&
      mapEquals(other.trashedAtMs, trashedAtMs);

  @override
  int get hashCode => Object.hash(
        sort,
        Object.hashAllUnordered(pinnedIds),
        Object.hashAllUnordered(archivedIds),
        Object.hashAllUnordered(trashedAtMs.entries.map((e) => e.key)),
      );
}
