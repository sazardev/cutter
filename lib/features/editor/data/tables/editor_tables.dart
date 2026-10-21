import 'package:drift/drift.dart';

// Drift column getters are declarative, and `check(column...)` is the
// documented way to reference the column being defined.
// ignore_for_file: public_member_api_docs, recursive_getters

/// Layer kinds allowed by the `kind` CHECK constraint.
const editorLayerKinds = ['video', 'image', 'audio'];

/// One editing project: canvas settings plus timestamps.
@DataClassName('EditorProject')
class EditorProjects extends Table {
  TextColumn get id => text()();

  TextColumn get name => text()();

  IntColumn get createdAtMs => integer()();

  IntColumn get updatedAtMs => integer()();

  IntColumn get canvasWidth =>
      integer().check(canvasWidth.isBiggerThanValue(0))();

  IntColumn get canvasHeight =>
      integer().check(canvasHeight.isBiggerThanValue(0))();

  IntColumn get fps => integer().check(fps.isBiggerThanValue(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A layer of a project; `position` 0 is the front-most row.
@DataClassName('EditorLayer')
class EditorLayers extends Table {
  TextColumn get id => text()();

  TextColumn get projectId =>
      text().references(EditorProjects, #id, onDelete: KeyAction.cascade)();

  IntColumn get position =>
      integer().check(position.isBiggerOrEqualValue(0))();

  TextColumn get kind => text().check(kind.isIn(editorLayerKinds))();

  RealColumn get volume => real().withDefault(const Constant(1))();

  BoolColumn get muted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A clip on a layer; times are integer milliseconds.
@DataClassName('EditorClip')
class EditorClips extends Table {
  TextColumn get id => text()();

  TextColumn get layerId =>
      text().references(EditorLayers, #id, onDelete: KeyAction.cascade)();

  IntColumn get sortKey => integer()();

  TextColumn get sourceUri => text()();

  IntColumn get startMs => integer().check(startMs.isBiggerOrEqualValue(0))();

  IntColumn get durationMs =>
      integer().check(durationMs.isBiggerThanValue(0))();

  IntColumn get inPointMs =>
      integer().check(inPointMs.isBiggerOrEqualValue(0))();

  IntColumn get outPointMs =>
      integer().check(outPointMs.isBiggerThanValue(0))();

  BoolColumn get reversed => boolean().withDefault(const Constant(false))();

  RealColumn get volume => real().withDefault(const Constant(1))();

  TextColumn get filterId => text().nullable()();

  /// JSON map of adjustment key to value (brightness, contrast, saturation).
  TextColumn get adjustmentsJson => text().withDefault(const Constant('{}'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
