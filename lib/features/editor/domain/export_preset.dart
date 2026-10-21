import 'package:cutter/features/editor/domain/canvas.dart';

/// Where a video is going: it decides the shape, the frame rate cap and the
/// size budget of the render.
enum ExportPlatform {
  /// The project's own canvas.
  project(null, 120),

  /// TikTok, Reels and Shorts: vertical.
  vertical(CanvasPreset.portrait, 60),

  /// YouTube and other players: widescreen.
  widescreen(CanvasPreset.landscape, 60),

  /// Instagram feed posts: 4:5.
  feed(CanvasPreset.feed, 30),

  /// Messaging (WhatsApp and the like): the project's shape, small files.
  messaging(null, 30);

  const ExportPlatform(this.canvas, this.maxFps);

  /// The shape it forces, or null to keep the project's.
  final CanvasPreset? canvas;

  /// The highest frame rate it accepts.
  final int maxFps;
}

/// How much care, time and space a render gets.
enum ExportQuality {
  /// Quick check: 720p, fast encoding, small.
  draft(720, 0.07, 'veryfast', 128000),

  /// Everyday sharing: 1080p.
  standard(1080, 0.1, 'fast', 192000),

  /// Best 1080p: higher bitrate, slower encoding.
  high(1080, 0.16, 'medium', 256000),

  /// 4K on the short side 2160.
  ultra(2160, 0.1, 'fast', 256000);

  const ExportQuality(
    this.shortSide,
    this.bitsPerPixel,
    this.encoderPreset,
    this.audioBitrate,
  );

  /// Pixels on the short side.
  final int shortSide;

  /// Video bits per pixel per frame; bitrate = pixels x fps x this.
  final double bitsPerPixel;

  /// The encoder effort.
  final String encoderPreset;

  /// Audio bits per second.
  final int audioBitrate;
}

/// The exact render a platform and quality give for a canvas.
class ExportPlan {
  /// Creates a plan.
  const ExportPlan({
    required this.width,
    required this.height,
    required this.fps,
    required this.videoBitrate,
    required this.audioBitrate,
    required this.encoderPreset,
    required this.reframed,
  });

  /// Picks the render of [canvas] for [platform] at [quality] and [fps].
  factory ExportPlan.of(
    Canvas canvas,
    ExportPlatform platform,
    ExportQuality quality,
    int fps,
  ) {
    final shape = platform.canvas;
    final width = shape?.width ?? canvas.width;
    final height = shape?.height ?? canvas.height;
    final messaging = platform == ExportPlatform.messaging;
    final shortSide =
        messaging && quality.shortSide > 720 ? 720 : quality.shortSide;
    final portrait = height >= width;
    final ratio = portrait ? height / width : width / height;
    final long = ((shortSide * ratio).round()) & ~1;
    final w = portrait ? shortSide : long;
    final h = portrait ? long : shortSide;
    final rate = fps.clamp(1, platform.maxFps);
    final bpp = messaging ? quality.bitsPerPixel * 0.6 : quality.bitsPerPixel;
    return ExportPlan(
      width: w,
      height: h,
      fps: rate,
      videoBitrate: (w * h * rate * bpp).round().clamp(500000, 80000000),
      audioBitrate: messaging ? 128000 : quality.audioBitrate,
      encoderPreset: quality.encoderPreset,
      reframed: shape != null &&
          (shape.width / shape.height - canvas.aspectRatio).abs() > 0.01,
    );
  }

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// Frames per second.
  final int fps;

  /// Video bits per second.
  final int videoBitrate;

  /// Audio bits per second.
  final int audioBitrate;

  /// The encoder effort.
  final String encoderPreset;

  /// True when the platform's shape differs from the project's: pictures
  /// are fitted to it again.
  final bool reframed;

  /// The expected size of a render of [durationMs], in bytes.
  int estimatedBytes(int durationMs) =>
      ((videoBitrate + audioBitrate) * durationMs / 8000).round();
}
