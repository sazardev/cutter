import 'package:cutter/core/db/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;
import 'generated/schema_v5.dart' as v5;
import 'generated/schema_v6.dart' as v6;

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

  group('migration from v2 to v3', () {
    // Version 3 adds the settings table. Nothing else changes, so the rows
    // of version 2 survive and the new table starts empty.
    test('keeps the projects and creates an empty settings table', () async {
      await verifier.testWithDataIntegrity(
        oldVersion: 2,
        newVersion: 3,
        createOld: v2.DatabaseAtV2.new,
        createNew: v3.DatabaseAtV3.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) {
          batch.insert(
            oldDb.editorProjects,
            const v2.EditorProjectsData(
              id: 'p1',
              name: 'Project',
              createdAtMs: 0,
              updatedAtMs: 0,
              canvasWidth: 1080,
              canvasHeight: 1920,
              fps: 30,
            ),
          );
        },
        validateItems: (newDb) async {
          final projects = await newDb.select(newDb.editorProjects).get();
          expect(projects.single.id, 'p1');
          expect(await newDb.select(newDb.appSettings).get(), isEmpty);
        },
      );
    });
  });

  group('migration from v3 to v4', () {
    // Version 4 adds the clip transform, the source size, the saved-at time
    // and the versions table. Old clips must come out fitted and centred,
    // and old projects as drafts.
    test('keeps the clips, fitted and centred, and projects as drafts',
        () async {
      await verifier.testWithDataIntegrity(
        oldVersion: 3,
        newVersion: 4,
        createOld: v3.DatabaseAtV3.new,
        createNew: v4.DatabaseAtV4.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) {
          batch
            ..insert(
              oldDb.editorProjects,
              const v3.EditorProjectsData(
                id: 'p1',
                name: 'Project',
                createdAtMs: 0,
                updatedAtMs: 5,
                canvasWidth: 1080,
                canvasHeight: 1920,
                fps: 30,
              ),
            )
            ..insert(
              oldDb.editorLayers,
              const v3.EditorLayersData(
                id: 'l1',
                projectId: 'p1',
                position: 0,
                kind: 'video',
                volume: 1,
                muted: 0,
              ),
            )
            ..insert(
              oldDb.editorClips,
              const v3.EditorClipsData(
                id: 'c1',
                layerId: 'l1',
                sortKey: 0,
                sourceUri: '/v.mp4',
                startMs: 0,
                durationMs: 1000,
                inPointMs: 0,
                outPointMs: 1000,
                reversed: 0,
                volume: 1,
                adjustmentsJson: '{}',
                sourceDurationMs: 4000,
              ),
            );
        },
        validateItems: (newDb) async {
          final clip = (await newDb.select(newDb.editorClips).get()).single;
          expect(clip.sourceDurationMs, 4000);
          expect((clip.posX, clip.posY, clip.scale), (0.0, 0.0, 1.0));
          expect((clip.rotation, clip.opacity, clip.flipX), (0.0, 1.0, 0));
          expect(clip.fit, 'fit');
          final project =
              (await newDb.select(newDb.editorProjects).get()).single;
          expect(project.savedAtMs, equals(null));
          expect(await newDb.select(newDb.editorVersions).get(), isEmpty);
        },
      );
    });
  });

  group('migration from v4 to v5', () {
    // Version 5 adds crop, speed and fades to clips and the exports table;
    // old clips keep the whole picture at normal speed.
    test('keeps the clips at normal speed, uncropped, without fades', () async {
      await verifier.testWithDataIntegrity(
        oldVersion: 4,
        newVersion: 5,
        createOld: v4.DatabaseAtV4.new,
        createNew: v5.DatabaseAtV5.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) {
          batch
            ..insert(
              oldDb.editorProjects,
              const v4.EditorProjectsData(
                id: 'p1',
                name: 'Project',
                createdAtMs: 0,
                updatedAtMs: 0,
                canvasWidth: 1920,
                canvasHeight: 1080,
                fps: 30,
              ),
            )
            ..insert(
              oldDb.editorLayers,
              const v4.EditorLayersData(
                id: 'l1',
                projectId: 'p1',
                position: 0,
                kind: 'video',
                volume: 1,
                muted: 0,
              ),
            )
            ..insert(
              oldDb.editorClips,
              const v4.EditorClipsData(
                id: 'c1',
                layerId: 'l1',
                sortKey: 0,
                sourceUri: '/v.mp4',
                startMs: 0,
                durationMs: 1000,
                inPointMs: 0,
                outPointMs: 1000,
                reversed: 0,
                volume: 1,
                adjustmentsJson: '{}',
                posX: 0.2,
                posY: 0,
                scale: 0.5,
                rotation: 0,
                opacity: 1,
                flipX: 0,
                fit: 'fit',
                sourceWidth: 1920,
                sourceHeight: 1080,
              ),
            );
        },
        validateItems: (newDb) async {
          final clip = (await newDb.select(newDb.editorClips).get()).single;
          expect((clip.posX, clip.scale), (0.2, 0.5));
          expect((clip.cropLeft, clip.cropRight, clip.speed), (0.0, 0.0, 1.0));
          expect((clip.fadeInMs, clip.fadeOutMs), (0, 0));
          expect(await newDb.select(newDb.editorExports).get(), isEmpty);
        },
      );
    });
  });

  group('migration from v5 to v6', () {
    // Version 6 adds the media bank and fills it with the files the clips
    // already use, once per project.
    test('puts the files of existing clips into their project bank', () async {
      await verifier.testWithDataIntegrity(
        oldVersion: 5,
        newVersion: 6,
        createOld: v5.DatabaseAtV5.new,
        createNew: v6.DatabaseAtV6.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) {
          batch
            ..insert(
              oldDb.editorProjects,
              const v5.EditorProjectsData(
                id: 'p1',
                name: 'Project',
                createdAtMs: 0,
                updatedAtMs: 9,
                canvasWidth: 1920,
                canvasHeight: 1080,
                fps: 30,
              ),
            )
            ..insert(
              oldDb.editorLayers,
              const v5.EditorLayersData(
                id: 'l1',
                projectId: 'p1',
                position: 0,
                kind: 'video',
                volume: 1,
                muted: 0,
              ),
            );
          for (final (id, start) in [('c1', 0), ('c2', 2000)]) {
            batch.insert(
              oldDb.editorClips,
              v5.EditorClipsData(
                id: id,
                layerId: 'l1',
                sortKey: start,
                sourceUri: '/v.mp4',
                startMs: start,
                durationMs: 1000,
                inPointMs: 0,
                outPointMs: 1000,
                reversed: 0,
                volume: 1,
                adjustmentsJson: '{}',
                sourceDurationMs: 8000,
                posX: 0,
                posY: 0,
                scale: 1,
                rotation: 0,
                opacity: 1,
                flipX: 0,
                fit: 'fit',
                sourceWidth: 1920,
                sourceHeight: 1080,
                cropLeft: 0,
                cropTop: 0,
                cropRight: 0,
                cropBottom: 0,
                speed: 1,
                fadeInMs: 0,
                fadeOutMs: 0,
              ),
            );
          }
        },
        validateItems: (newDb) async {
          final media = await newDb.select(newDb.editorMedia).get();
          expect(media, hasLength(1));
          expect(
            (media.single.path, media.single.kind, media.single.durationMs),
            ('/v.mp4', 'video', 8000),
          );
          expect(media.single.projectId, 'p1');
        },
      );
    });
  });
}
