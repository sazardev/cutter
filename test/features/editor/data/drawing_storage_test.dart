import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/features/editor/data/drift_project_repository.dart';
import 'package:cutter/features/editor/data/editor_dao.dart';
import 'package:cutter/features/editor/data/project_snapshot_codec.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/clip_drawing.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

Project _drawn() => Project(
      id: 'p',
      name: 'Drawn',
      layers: [
        Layer(
          id: 'l1',
          name: '',
          kind: MediaKind.image,
          clips: const [
            Clip(
              id: 'd1',
              layerId: 'l1',
              assetId: '/drawings/d1.png',
              sourceUri: '/drawings/d1.png',
              kind: MediaKind.image,
              startMs: 0,
              inPointMs: 0,
              outPointMs: 3000,
              sourceDurationMs: 3000,
              sourceWidth: 1080,
              sourceHeight: 1920,
              drawing: ClipDrawing([
                DrawingStroke(
                  color: 0xFF1E88E5,
                  width: 0.03,
                  points: [0.1, 0.1, 0.5, 0.6],
                ),
              ]),
            ),
          ],
        ),
      ],
    );

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase.inMemory());
  tearDown(() => database.close());

  test('a saved project keeps its drawing', () async {
    final repository = DriftProjectRepository(EditorDao(database));
    await repository.save(_drawn());

    expect(await repository.find('p'), _drawn());
  });

  test('a clip that is not a drawing loads without one', () async {
    final repository = DriftProjectRepository(EditorDao(database));
    final plain = Project(
      id: 'q',
      name: 'Plain',
      layers: [
        Layer(
          id: 'l',
          name: '',
          kind: MediaKind.image,
          clips: const [
            Clip(
              id: 'c',
              layerId: 'l',
              assetId: '/a.png',
              sourceUri: '/a.png',
              kind: MediaKind.image,
              startMs: 0,
              inPointMs: 0,
              outPointMs: 3000,
              sourceDurationMs: 3000,
            ),
          ],
        ),
      ],
    );
    await repository.save(plain);

    expect((await repository.find('q'))!.clipById('c')!.drawing, isNull);
  });

  test('a saved version keeps its drawing', () {
    expect(decodeProjectSnapshot(encodeProjectSnapshot(_drawn())), _drawn());
  });
}
