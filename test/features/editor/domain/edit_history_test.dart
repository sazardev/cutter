import 'package:cutter/features/editor/domain/edit_history.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

Project _version(int n) => Project(id: 'p', name: 'v$n');

void main() {
  test('starts with nothing to undo or redo', () {
    final history = EditHistory();

    expect(history.canUndo, isFalse);
    expect(history.canRedo, isFalse);
    expect(history.undo(_version(0)), isNull);
    expect(history.redo(_version(0)), isNull);
  });

  test('undo walks back and redo walks forward again', () {
    final history = EditHistory()
      ..record(_version(0))
      ..record(_version(1));

    expect(history.undo(_version(2)), _version(1));
    expect(history.undo(_version(1)), _version(0));
    expect(history.canUndo, isFalse);
    expect(history.redo(_version(0)), _version(1));
    expect(history.redo(_version(1)), _version(2));
    expect(history.canRedo, isFalse);
  });

  test('a new edit after an undo drops the redo branch', () {
    final history = EditHistory()
      ..record(_version(0))
      ..record(_version(1))
      ..undo(_version(2))
      ..record(_version(1));

    expect(history.canRedo, isFalse);
  });

  test('forgets the oldest steps past the limit', () {
    final history = EditHistory(limit: 2)
      ..record(_version(0))
      ..record(_version(1))
      ..record(_version(2));

    expect(history.undo(_version(3)), _version(2));
    expect(history.undo(_version(2)), _version(1));
    expect(history.canUndo, isFalse);
  });
}
