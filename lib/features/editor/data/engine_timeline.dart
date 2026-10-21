import 'package:cutter/core/engine/media_engine.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/clip_transform.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/project.dart';

/// The engine's kind for a domain [kind].
EngineMediaKind engineKindOf(MediaKind kind) => switch (kind) {
      MediaKind.video => EngineMediaKind.video,
      MediaKind.image => EngineMediaKind.image,
      MediaKind.audio => EngineMediaKind.audio,
    };

/// A file path for a stored source URI: clips store plain paths, older ones
/// `file://` URIs.
String filePathOf(String uri) =>
    uri.startsWith('file://') ? Uri.parse(uri).toFilePath() : uri;

/// What the engine renders for [project]. [adjustmentOverrides] and
/// [transformOverrides] replace the values of clips by id, so a slider or a
/// gesture shows its result before it is saved. Clips whose source is in
/// [missingSources] are left out, so a file that went missing never reaches
/// the engine.
Timeline engineTimelineOf(
  Project project, {
  Set<String> missingSources = const {},
  Map<String, Map<String, double>> adjustmentOverrides = const {},
  Map<String, ClipTransform> transformOverrides = const {},
}) {
  return Timeline(
    width: project.canvas.width,
    height: project.canvas.height,
    fps: project.canvas.fps,
    layers: [
      for (final layer in project.layers)
        TimelineLayer(
          kind: engineKindOf(layer.kind),
          volume: layer.volume,
          muted: layer.muted,
          clips: [
            for (final clip in layer.clips)
              if (!missingSources.contains(clip.sourceUri))
                () {
                  final adjustments =
                      adjustmentOverrides[clip.id] ?? clip.adjustments;
                  final t = transformOverrides[clip.id] ?? clip.transform;
                  return TimelineClip(
                    path: filePathOf(clip.sourceUri),
                    kind: engineKindOf(clip.kind),
                    startMs: clip.startMs,
                    inMs: clip.inPointMs,
                    outMs: clip.outPointMs,
                    reversed: clip.reversed,
                    volume: clip.volume,
                    filter: clip.filterId,
                    brightness: adjustments['brightness'] ?? 0,
                    contrast: adjustments['contrast'] ?? 0,
                    saturation: adjustments['saturation'] ?? 0,
                    x: t.x,
                    y: t.y,
                    scale: t.scale,
                    rotation: t.rotation,
                    opacity: t.opacity,
                    flipX: t.flipX,
                    fill: t.fit == ClipFit.fill,
                    cropLeft: clip.crop.left,
                    cropTop: clip.crop.top,
                    cropRight: clip.crop.right,
                    cropBottom: clip.crop.bottom,
                    speed: clip.speed,
                    fadeInMs: clip.fadeInMs,
                    fadeOutMs: clip.fadeOutMs,
                  );
                }(),
          ],
        ),
    ],
  );
}

/// Where the picture of [clip] sits on a canvas of [canvasWidth] x
/// [canvasHeight], with [transform]: its centre, its size before rotation,
/// and its clockwise rotation in degrees. Mirrors the engine's placement so
/// the editor can draw selection frames and hit-test pictures; null when
/// the size of the source is unknown.
({double cx, double cy, double width, double height, double rotation})?
    placementOf(
  Clip clip,
  ClipTransform transform,
  double canvasWidth,
  double canvasHeight,
) {
  if (clip.sourceWidth <= 0 || clip.sourceHeight <= 0) return null;
  // Fit and fill work on the kept part of the picture, as in the engine.
  final sw = clip.sourceWidth * clip.crop.keptWidth;
  final sh = clip.sourceHeight * clip.crop.keptHeight;
  final fitW = canvasWidth / sw;
  final fitH = canvasHeight / sh;
  final base = transform.fit == ClipFit.fill
      ? (fitW > fitH ? fitW : fitH)
      : (fitW < fitH ? fitW : fitH);
  final scale = base * transform.scale;
  return (
    cx: canvasWidth / 2 + transform.x * canvasWidth,
    cy: canvasHeight / 2 + transform.y * canvasHeight,
    width: sw * scale,
    height: sh * scale,
    rotation: transform.rotation,
  );
}
