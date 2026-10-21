import 'package:cutter/features/settings/domain/changelog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads releases, groups and bullets in file order', () {
    final releases = parseChangelog('''
# Changelog

Intro text that is ignored.

## [0.2.0] - 2026-11-01

### Added
- One
- Two

### Fixed
- Three

## [0.1.0]

### Added
- First
''');

    expect(releases.map((r) => r.version), ['0.2.0', '0.1.0']);
    expect(releases.first.date, '2026-11-01');
    expect(releases.first.groups.map((g) => g.title), ['Added', 'Fixed']);
    expect(releases.first.groups.first.items, ['One', 'Two']);
    expect(releases.last.date, isEmpty);
  });

  test('an empty or heading-less file has no releases', () {
    expect(parseChangelog(''), isEmpty);
    expect(parseChangelog('# Changelog\n- stray'), isEmpty);
  });
}
