/// One heading of a release and its bullet points, e.g. "Added".
class ChangelogGroup {
  /// Creates a group.
  const ChangelogGroup(this.title, this.items);

  /// The group heading ("Added", "Fixed"...).
  final String title;

  /// The bullet points.
  final List<String> items;
}

/// One released version.
class ChangelogRelease {
  /// Creates a release.
  const ChangelogRelease(this.version, this.date, this.groups);

  /// The version, without brackets.
  final String version;

  /// The release date as written, or empty.
  final String date;

  /// The groups, in file order.
  final List<ChangelogGroup> groups;
}

/// Reads a Keep a Changelog file: `## [1.0.0] - 2026-01-01` releases,
/// `### Added` groups and `- item` bullets. Anything else is ignored.
List<ChangelogRelease> parseChangelog(String markdown) {
  final releases = <ChangelogRelease>[];
  String? version;
  var date = '';
  var groups = <ChangelogGroup>[];
  String? groupTitle;
  var items = <String>[];

  void closeGroup() {
    if (groupTitle != null && items.isNotEmpty) {
      groups.add(ChangelogGroup(groupTitle!, items));
    }
    groupTitle = null;
    items = [];
  }

  void closeRelease() {
    closeGroup();
    if (version != null) {
      releases.add(ChangelogRelease(version!, date, groups));
    }
    version = null;
    date = '';
    groups = [];
  }

  final releaseHeading = RegExp(r'^##\s+\[?([^\]\s]+)\]?(?:\s*[-–]\s*(.+))?$');
  for (final raw in markdown.split('\n')) {
    final line = raw.trimRight();
    if (line.startsWith('## ')) {
      closeRelease();
      final match = releaseHeading.firstMatch(line);
      version = match?.group(1);
      date = match?.group(2)?.trim() ?? '';
    } else if (line.startsWith('### ') && version != null) {
      closeGroup();
      groupTitle = line.substring(4).trim();
    } else if (line.startsWith('- ') && groupTitle != null) {
      items.add(line.substring(2).trim());
    }
  }
  closeRelease();
  return releases;
}
