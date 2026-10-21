import 'dart:convert';

import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/features/editor/data/editor_dao.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_kind.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/domain/project_repository.dart';

/// Drift-backed [ProjectRepository]: maps stored rows to the immutable
/// domain entities and back.
class DriftProjectRepository implements ProjectRepository {
  /// Creates a repository that reads and writes through [_dao].
  DriftProjectRepository(this._dao);

  final EditorDao _dao;

  static const _defaultCanvasWidth = 1080;
  static const _defaultCanvasHeight = 1920;
  static const _defaultFps = 30;

  // Layer names are not stored; the timeline labels layers by position.
  static const _unnamedLayer = '';

  @override
  Future<Project?> load(String id) async {
    final rows = await _dao.loadProjectRows(id);
    if (rows == null) {
      return null;
    }
    return _projectFromRows(rows);
  }

  @override
  Future<void> save(Project project) async {
    final existing = await _dao.loadProjectRows(project.id);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _dao.replaceProject(
      _rowsFromProject(project, existing?.project, nowMs),
    );
  }

  /// The oldest stored project id, or null when nothing is stored.
  Future<String?> firstProjectId() => _dao.firstProjectId();

  Project _projectFromRows(ProjectRows rows) {
    final clipsByLayer = <String, List<EditorClip>>{};
    for (final clip in rows.clips) {
      clipsByLayer.putIfAbsent(clip.layerId, () => []).add(clip);
    }

    final layers = [
      for (final layer in rows.layers)
        _layerFromRow(layer, clipsByLayer[layer.id] ?? const []),
    ];

    final header = rows.project;
    return Project(
      id: header.id,
      name: header.name,
      layers: layers,
    );
  }

  Layer _layerFromRow(EditorLayer row, List<EditorClip> clipRows) {
    final kind = MediaKind.values.byName(row.kind);
    final clips = clipRows.map((clip) => _clipFromRow(clip, kind)).toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    return Layer(
      id: row.id,
      name: _unnamedLayer,
      kind: kind,
      volume: row.volume,
      muted: row.muted,
      clips: clips,
    );
  }

  Clip _clipFromRow(EditorClip row, MediaKind kind) {
    final decoded = jsonDecode(row.adjustmentsJson) as Map<String, dynamic>;
    return Clip(
      id: row.id,
      layerId: row.layerId,
      assetId: row.sourceUri,
      kind: kind,
      sourceUri: row.sourceUri,
      sourceDurationMs: row.outPointMs,
      startMs: row.startMs,
      inPointMs: row.inPointMs,
      outPointMs: row.outPointMs,
      reversed: row.reversed,
      volume: row.volume,
      filterId: row.filterId,
      adjustments: {
        for (final entry in decoded.entries)
          entry.key: (entry.value as num).toDouble(),
      },
    );
  }

  ProjectRows _rowsFromProject(
    Project project,
    EditorProject? existing,
    int nowMs,
  ) {
    final layerRows = <EditorLayer>[];
    final clipRows = <EditorClip>[];

    for (var position = 0; position < project.layers.length; position++) {
      final layer = project.layers[position];
      layerRows.add(
        EditorLayer(
          id: layer.id,
          projectId: project.id,
          position: position,
          kind: layer.kind.name,
          volume: layer.volume,
          muted: layer.muted,
        ),
      );

      final sorted = [...layer.clips]
        ..sort((a, b) => a.startMs.compareTo(b.startMs));
      for (var sortKey = 0; sortKey < sorted.length; sortKey++) {
        clipRows.add(_clipToRow(sorted[sortKey], layer.id, sortKey));
      }
    }

    return ProjectRows(
      project: EditorProject(
        id: project.id,
        name: project.name,
        createdAtMs: existing?.createdAtMs ?? nowMs,
        updatedAtMs: nowMs,
        canvasWidth: existing?.canvasWidth ?? _defaultCanvasWidth,
        canvasHeight: existing?.canvasHeight ?? _defaultCanvasHeight,
        fps: existing?.fps ?? _defaultFps,
      ),
      layers: layerRows,
      clips: clipRows,
    );
  }

  EditorClip _clipToRow(Clip clip, String layerId, int sortKey) {
    return EditorClip(
      id: clip.id,
      layerId: layerId,
      sortKey: sortKey,
      sourceUri: clip.sourceUri,
      startMs: clip.startMs,
      durationMs: clip.durationMs,
      inPointMs: clip.inPointMs,
      outPointMs: clip.outPointMs,
      reversed: clip.reversed,
      volume: clip.volume,
      filterId: clip.filterId,
      adjustmentsJson: jsonEncode(clip.adjustments),
    );
  }
}
