import 'dart:convert';

import 'package:cutter/features/editor/domain/canvas.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/clip_crop.dart';
import 'package:cutter/features/editor/domain/clip_drawing.dart';
import 'package:cutter/features/editor/domain/clip_text.dart';
import 'package:cutter/features/editor/domain/clip_transform.dart';
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';

/// Version of the snapshot format, stored in every snapshot so a later
/// format can still read older versions. Format 2 adds crop, speed and
/// fades; format 3 adds text clips; format 4 adds animations; format 5 adds
/// drawings. Older snapshots read with defaults.
const snapshotFormat = 5;

/// A whole project as JSON, for saved versions.
String encodeProjectSnapshot(Project project) => jsonEncode({
      'format': snapshotFormat,
      'id': project.id,
      'name': project.name,
      'templateId': project.templateId,
      'canvas': {
        'width': project.canvas.width,
        'height': project.canvas.height,
        'fps': project.canvas.fps,
      },
      'layers': [
        for (final layer in project.layers)
          {
            'id': layer.id,
            'name': layer.name,
            'kind': layer.kind.name,
            'volume': layer.volume,
            'muted': layer.muted,
            'clips': [for (final clip in layer.clips) _clip(clip)],
          },
      ],
    });

Map<String, Object?> _clip(Clip clip) => {
      'id': clip.id,
      'assetId': clip.assetId,
      'sourceUri': clip.sourceUri,
      'kind': clip.kind.name,
      'startMs': clip.startMs,
      'inPointMs': clip.inPointMs,
      'outPointMs': clip.outPointMs,
      'sourceDurationMs': clip.sourceDurationMs,
      'reversed': clip.reversed,
      'volume': clip.volume,
      'filterId': clip.filterId,
      'adjustments': clip.adjustments,
      'sourceWidth': clip.sourceWidth,
      'sourceHeight': clip.sourceHeight,
      'crop': [
        clip.crop.left,
        clip.crop.top,
        clip.crop.right,
        clip.crop.bottom,
      ],
      'speed': clip.speed,
      'fadeInMs': clip.fadeInMs,
      'fadeOutMs': clip.fadeOutMs,
      'text': clip.text?.toJson(),
      'animIn': clip.animIn,
      'animInMs': clip.animInMs,
      'animOut': clip.animOut,
      'animOutMs': clip.animOutMs,
      'drawing': clip.drawing?.toJson(),
      'transform': {
        'x': clip.transform.x,
        'y': clip.transform.y,
        'scale': clip.transform.scale,
        'rotation': clip.transform.rotation,
        'opacity': clip.transform.opacity,
        'flipX': clip.transform.flipX,
        'fit': clip.transform.fit.name,
      },
    };

/// The project stored in [json] by [encodeProjectSnapshot].
Project decodeProjectSnapshot(String json) {
  final map = jsonDecode(json) as Map<String, dynamic>;
  final canvas = map['canvas'] as Map<String, dynamic>;
  return Project(
    id: map['id'] as String,
    name: map['name'] as String,
    templateId: map['templateId'] as String?,
    canvas: Canvas(
      width: canvas['width'] as int,
      height: canvas['height'] as int,
      fps: canvas['fps'] as int,
    ),
    layers: [
      for (final raw in map['layers'] as List<dynamic>)
        _layer(raw as Map<String, dynamic>),
    ],
  );
}

Layer _layer(Map<String, dynamic> map) {
  final id = map['id'] as String;
  return Layer(
    id: id,
    name: map['name'] as String,
    kind: MediaKind.values.byName(map['kind'] as String),
    volume: (map['volume'] as num).toDouble(),
    muted: map['muted'] as bool,
    clips: [
      for (final raw in map['clips'] as List<dynamic>)
        _clipFrom(raw as Map<String, dynamic>, id),
    ],
  );
}

Clip _clipFrom(Map<String, dynamic> map, String layerId) {
  final t = map['transform'] as Map<String, dynamic>;
  final crop = (map['crop'] as List<dynamic>?)
      ?.map((v) => (v as num).toDouble())
      .toList();
  final adjustments = map['adjustments'] as Map<String, dynamic>;
  return Clip(
    id: map['id'] as String,
    layerId: layerId,
    assetId: map['assetId'] as String,
    sourceUri: map['sourceUri'] as String,
    kind: MediaKind.values.byName(map['kind'] as String),
    startMs: map['startMs'] as int,
    inPointMs: map['inPointMs'] as int,
    outPointMs: map['outPointMs'] as int,
    sourceDurationMs: map['sourceDurationMs'] as int,
    reversed: map['reversed'] as bool,
    volume: (map['volume'] as num).toDouble(),
    filterId: map['filterId'] as String?,
    adjustments: {
      for (final entry in adjustments.entries)
        entry.key: (entry.value as num).toDouble(),
    },
    sourceWidth: map['sourceWidth'] as int,
    sourceHeight: map['sourceHeight'] as int,
    crop: crop == null
        ? const ClipCrop()
        : ClipCrop(
            left: crop[0],
            top: crop[1],
            right: crop[2],
            bottom: crop[3],
          ),
    speed: (map['speed'] as num?)?.toDouble() ?? 1,
    fadeInMs: map['fadeInMs'] as int? ?? 0,
    fadeOutMs: map['fadeOutMs'] as int? ?? 0,
    text: map['text'] == null
        ? null
        : ClipText.fromJson(map['text'] as Map<String, dynamic>),
    animIn: map['animIn'] as String?,
    animInMs: map['animInMs'] as int? ?? 0,
    animOut: map['animOut'] as String?,
    animOutMs: map['animOutMs'] as int? ?? 0,
    drawing: map['drawing'] == null
        ? null
        : ClipDrawing.fromJson(map['drawing'] as Map<String, dynamic>),
    transform: ClipTransform(
      x: (t['x'] as num).toDouble(),
      y: (t['y'] as num).toDouble(),
      scale: (t['scale'] as num).toDouble(),
      rotation: (t['rotation'] as num).toDouble(),
      opacity: (t['opacity'] as num).toDouble(),
      flipX: t['flipX'] as bool,
      fit: ClipFit.values.byName(t['fit'] as String),
    ),
  );
}
