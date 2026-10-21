import 'package:cutter/features/editor/domain/project.dart';

/// The undo and redo stacks of one editing session. Projects are immutable,
/// so a step is the whole project as it was.
class EditHistory {
  /// Creates an empty history keeping at most [limit] undo steps.
  EditHistory({this.limit = 100});

  /// The most undo steps kept; older ones are forgotten.
  final int limit;

  final List<Project> _undo = [];
  final List<Project> _redo = [];

  /// Whether there is a step to undo.
  bool get canUndo => _undo.isNotEmpty;

  /// Whether there is an undone step to redo.
  bool get canRedo => _redo.isNotEmpty;

  /// Remembers [before], the project as it was before an edit. A new edit
  /// drops whatever could have been redone.
  void record(Project before) {
    _undo.add(before);
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
  }

  /// The project to go back to from [current], or null when there is none.
  Project? undo(Project current) {
    if (_undo.isEmpty) return null;
    _redo.add(current);
    return _undo.removeLast();
  }

  /// The project to go forward to from [current], or null when there is
  /// none.
  Project? redo(Project current) {
    if (_redo.isEmpty) return null;
    _undo.add(current);
    return _redo.removeLast();
  }
}
