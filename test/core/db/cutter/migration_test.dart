import 'package:cutter/core/db/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = AppDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  group('migration from v1 to v2', () {
    // Version 2 adds the column that holds the duration of the source media
    // of a clip. The rows of version 1 do not have it, so the migration
    // leaves the column empty and the repository falls back to the out
    // point. Everything else has to survive untouched.
    final oldEditorProjectsData = <v1.EditorProjectsData>[
      const v1.EditorProjectsData(
        id: 'p1',
        name: 'Project',
        createdAtMs: 0,
        updatedAtMs: 0,
        canvasWidth: 1080,
        canvasHeight: 1920,
        fps: 30,
      ),
    ];
    final oldEditorLayersData = <v1.EditorLayersData>[
      const v1.EditorLayersData(
        id: 'l1',
        projectId: 'p1',
        position: 0,
        kind: 'video',
        volume: 1,
        muted: 0,
      ),
    ];
    final oldEditorClipsData = <v1.EditorClipsData>[
      const v1.EditorClipsData(
        id: 'c1',
        layerId: 'l1',
        sortKey: 0,
        sourceUri: 'file:///clip.mp4',
        startMs: 0,
        durationMs: 4000,
        inPointMs: 0,
        outPointMs: 4000,
        reversed: 0,
        volume: 1,
        adjustmentsJson: '{}',
      ),
    ];

    final expectedNewEditorProjectsData = <v2.EditorProjectsData>[
      const v2.EditorProjectsData(
        id: 'p1',
        name: 'Project',
        createdAtMs: 0,
        updatedAtMs: 0,
        canvasWidth: 1080,
        canvasHeight: 1920,
        fps: 30,
      ),
    ];
    final expectedNewEditorLayersData = <v2.EditorLayersData>[
      const v2.EditorLayersData(
        id: 'l1',
        projectId: 'p1',
        position: 0,
        kind: 'video',
        volume: 1,
        muted: 0,
      ),
    ];
    final expectedNewEditorClipsData = <v2.EditorClipsData>[
      const v2.EditorClipsData(
        id: 'c1',
        layerId: 'l1',
        sortKey: 0,
        sourceUri: 'file:///clip.mp4',
        startMs: 0,
        durationMs: 4000,
        inPointMs: 0,
        outPointMs: 4000,
        reversed: 0,
        volume: 1,
        adjustmentsJson: '{}',
        // The column of version 2 is empty for the rows of version 1.
      ),
    ];

    test('keeps the rows and leaves the new column empty', () async {
      await verifier.testWithDataIntegrity(
        oldVersion: 1,
        newVersion: 2,
        createOld: v1.DatabaseAtV1.new,
        createNew: v2.DatabaseAtV2.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) {
          batch
            ..insertAll(oldDb.editorProjects, oldEditorProjectsData)
            ..insertAll(oldDb.editorLayers, oldEditorLayersData)
            ..insertAll(oldDb.editorClips, oldEditorClipsData);
        },
        validateItems: (newDb) async {
          expect(
            await newDb.select(newDb.editorProjects).get(),
            expectedNewEditorProjectsData,
          );
          expect(
            await newDb.select(newDb.editorLayers).get(),
            expectedNewEditorLayersData,
          );
          expect(
            await newDb.select(newDb.editorClips).get(),
            expectedNewEditorClipsData,
          );
        },
      );
    });
  });
}
