import 'dart:convert';

import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/features/editor/data/editor_dao.dart';
import 'package:cutter/features/editor/domain/canvas.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/clip_crop.dart';
import 'package:cutter/features/editor/domain/clip_drawing.dart';
import 'package:cutter/features/editor/domain/clip_text.dart';
import 'package:cutter/features/editor/domain/clip_transform.dart';
import 'package:cutter/features/editor/domain/editor_ports.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/domain/project_summary.dart';

/// Drift-backed [ProjectRepository]: maps stored rows to the immutable
/// domain entities and back.
class DriftProjectRepository implements ProjectRepository {
  /// Creates a repository that reads and writes through [_dao].
  DriftProjectRepository(this._dao);

  final EditorDao _dao;

  // Layer names are not stored; the timeline labels layers by position.
  static const _unnamedLayer = '';

  @override
  Future<Project?> find(String id) async {
    final rows = await _dao.loadProjectRows(id);
    if (rows == null) {
      return null;
    }
    return _projectFromRows(rows);
  }

  @override
  Future<void> delete(String id) => _dao.deleteProject(id);

  @override
  Future<void> save(Project project) async {
    final existing = await _dao.loadProjectRows(project.id);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _dao.replaceProject(
      _rowsFromProject(project, existing?.project, nowMs),
    );
  }

  @override
  Future<List<ProjectSummary>> summaries() => _dao.summaries();

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
      canvas: Canvas(
        width: header.canvasWidth,
        height: header.canvasHeight,
        fps: header.fps,
      ),
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
      // Rows written before version 2 do not carry the duration of their
      // source; version 1 rebuilt it from the out point.
      sourceDurationMs: row.sourceDurationMs ?? row.outPointMs,
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
      transform: ClipTransform(
        x: row.posX,
        y: row.posY,
        scale: row.scale,
        rotation: row.rotation,
        opacity: row.opacity,
        flipX: row.flipX,
        fit: ClipFit.values.byName(row.fit),
      ),
      sourceWidth: row.sourceWidth,
      sourceHeight: row.sourceHeight,
      crop: ClipCrop(
        left: row.cropLeft,
        top: row.cropTop,
        right: row.cropRight,
        bottom: row.cropBottom,
      ),
      speed: row.speed,
      fadeInMs: row.fadeInMs,
      fadeOutMs: row.fadeOutMs,
      text: row.textJson == null
          ? null
          : ClipText.fromJson(
              jsonDecode(row.textJson!) as Map<String, dynamic>,
            ),
      animIn: row.animIn,
      animInMs: row.animInMs,
      animOut: row.animOut,
      animOutMs: row.animOutMs,
      drawing: row.drawingJson == null
          ? null
          : ClipDrawing.fromJson(
              jsonDecode(row.drawingJson!) as Map<String, dynamic>,
            ),
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
        canvasWidth: project.canvas.width,
        canvasHeight: project.canvas.height,
        fps: project.canvas.fps,
        savedAtMs: existing?.savedAtMs,
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
      sourceDurationMs: clip.sourceDurationMs,
      posX: clip.transform.x,
      posY: clip.transform.y,
      scale: clip.transform.scale,
      rotation: clip.transform.rotation,
      opacity: clip.transform.opacity,
      flipX: clip.transform.flipX,
      fit: clip.transform.fit.name,
      sourceWidth: clip.sourceWidth,
      sourceHeight: clip.sourceHeight,
      cropLeft: clip.crop.left,
      cropTop: clip.crop.top,
      cropRight: clip.crop.right,
      cropBottom: clip.crop.bottom,
      speed: clip.speed,
      fadeInMs: clip.fadeInMs,
      fadeOutMs: clip.fadeOutMs,
      textJson: clip.text == null ? null : jsonEncode(clip.text!.toJson()),
      animIn: clip.animIn,
      animInMs: clip.animInMs,
      animOut: clip.animOut,
      animOutMs: clip.animOutMs,
      drawingJson:
          clip.drawing == null ? null : jsonEncode(clip.drawing!.toJson()),
    );
  }
}
