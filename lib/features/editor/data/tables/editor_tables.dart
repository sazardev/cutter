import 'package:drift/drift.dart';

// Drift column getters are declarative, and `check(column...)` is the
// documented way to reference the column being defined.
// ignore_for_file: public_member_api_docs, recursive_getters

/// Layer kinds allowed by the `kind` CHECK constraint.
const editorLayerKinds = ['video', 'image', 'audio'];

/// Clip fit modes allowed by the `fit` CHECK constraint.
const editorClipFits = ['fit', 'fill'];

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

  /// When a version was last saved by hand (version 4); null when never.
  IntColumn get savedAtMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A layer of a project; `position` 0 is the front-most row.
@DataClassName('EditorLayer')
class EditorLayers extends Table {
  TextColumn get id => text()();

  TextColumn get projectId =>
      text().references(EditorProjects, #id, onDelete: KeyAction.cascade)();

  IntColumn get position => integer().check(position.isBiggerOrEqualValue(0))();

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

  /// The full duration of the source media. Null for the rows written
  /// before version 2, which did not store it; the repository falls back to
  /// the out point for those.
  IntColumn get sourceDurationMs => integer().nullable()();

  // Version 4: where the picture sits on the canvas (see ClipTransform) and
  // the display size of the source.

  RealColumn get posX => real().withDefault(const Constant(0))();

  RealColumn get posY => real().withDefault(const Constant(0))();

  RealColumn get scale => real().withDefault(const Constant(1))();

  RealColumn get rotation => real().withDefault(const Constant(0))();

  RealColumn get opacity => real().withDefault(const Constant(1))();

  BoolColumn get flipX => boolean().withDefault(const Constant(false))();

  TextColumn get fit => text()
      .withDefault(const Constant('fit'))
      .check(fit.isIn(editorClipFits))();

  IntColumn get sourceWidth => integer().withDefault(const Constant(0))();

  IntColumn get sourceHeight => integer().withDefault(const Constant(0))();

  // Version 5: crop (fractions cut from each edge), speed and sound fades.

  RealColumn get cropLeft => real().withDefault(const Constant(0))();

  RealColumn get cropTop => real().withDefault(const Constant(0))();

  RealColumn get cropRight => real().withDefault(const Constant(0))();

  RealColumn get cropBottom => real().withDefault(const Constant(0))();

  RealColumn get speed => real().withDefault(const Constant(1))();

  IntColumn get fadeInMs => integer().withDefault(const Constant(0))();

  IntColumn get fadeOutMs => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A version of a project saved by hand: its name and the whole project as
/// JSON, so it can be restored even after the clips changed (version 4).
@DataClassName('EditorVersion')
class EditorVersions extends Table {
  TextColumn get id => text()();

  TextColumn get projectId =>
      text().references(EditorProjects, #id, onDelete: KeyAction.cascade)();

  TextColumn get name => text()();

  IntColumn get createdAtMs => integer()();

  IntColumn get durationMs => integer().withDefault(const Constant(0))();

  TextColumn get snapshotJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A video the app rendered (version 5). The project link is cleared when
/// the project is deleted; the video stays in the library.
@DataClassName('EditorExport')
class EditorExports extends Table {
  TextColumn get id => text()();

  TextColumn get projectId => text()
      .nullable()
      .references(EditorProjects, #id, onDelete: KeyAction.setNull)();

  TextColumn get projectName => text()();

  TextColumn get path => text()();

  IntColumn get width => integer()();

  IntColumn get height => integer()();

  IntColumn get fps => integer()();

  IntColumn get durationMs => integer()();

  IntColumn get sizeBytes => integer()();

  IntColumn get createdAtMs => integer()();

  TextColumn get preset => text()();

  BoolColumn get inGallery => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A file in a project's media bank (version 6). When the project is deleted
/// the row stays, unlinked, among the recent files.
@DataClassName('EditorMediaItem')
class EditorMedia extends Table {
  TextColumn get id => text()();

  TextColumn get projectId => text()
      .nullable()
      .references(EditorProjects, #id, onDelete: KeyAction.setNull)();

  TextColumn get path => text()();

  TextColumn get kind => text().check(kind.isIn(editorLayerKinds))();

  IntColumn get durationMs => integer()();

  IntColumn get width => integer().withDefault(const Constant(0))();

  IntColumn get height => integer().withDefault(const Constant(0))();

  BoolColumn get hasAudio => boolean().withDefault(const Constant(false))();

  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();

  IntColumn get addedAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {projectId, path},
      ];
}
