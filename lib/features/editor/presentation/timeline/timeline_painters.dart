import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cutter/features/editor/data/engine_timeline.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/presentation/time_format.dart';
import 'package:cutter/features/editor/presentation/timeline/media_previews.dart';
import 'package:cutter/features/editor/presentation/timeline/timeline_geometry.dart';
import 'package:flutter/material.dart';

/// The part of the timeline content on screen, in content pixels. Clip
/// painters draw (and ask thumbnails for) only what falls inside it, plus a
/// screen of margin, however long the clip is.
class TimelineViewport extends ChangeNotifier {
  double _left = 0;
  double _width = 0;

  /// Left edge of the screen in content pixels.
  double get left => _left;

  /// Width of the screen in content pixels.
  double get width => _width;

  /// Moves the window; listeners hear of it only when it moved.
  void update(double left, double width) {
    if (left == _left && width == _width) return;
    _left = left;
    _width = width;
    notifyListeners();
  }

  /// The visible span of something drawn from [contentLeft] with [length]
  /// pixels, in its own coordinates, widened by a screen on each side.
  (double, double) visibleIn(double contentLeft, double length) {
    if (_width <= 0) return (0, length);
    final from = (_left - _width - contentLeft).clamp(0.0, length);
    final to = (_left + 2 * _width - contentLeft).clamp(0.0, length);
    return (from, to);
  }
}

/// Minor ticks between two ruler labels.
const int _minorTicks = 5;

/// Time marks for the visible part of the timeline. The content is
/// [leadPx] wide before time zero, and scrolled by [offset].
class RulerPainter extends CustomPainter {
  /// Creates the ruler painter.
  RulerPainter({
    required this.offset,
    required this.zoom,
    required this.leadPx,
    required this.tickColor,
    required this.labelStyle,
    required this.textDirection,
  });

  /// Horizontal scroll offset of the tracks.
  final double offset;

  /// Logical pixels per millisecond.
  final double zoom;

  /// Width before time zero.
  final double leadPx;

  /// Colour of the tick marks.
  final Color tickColor;

  /// Style of the time labels.
  final TextStyle labelStyle;

  /// Direction of the labels' text.
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final step = rulerStepMs(zoom);
    final minor = step / _minorTicks;
    final firstMs = math.max(0, (offset - leadPx) / zoom);
    final lastMs = (offset - leadPx + size.width) / zoom;
    final paint = Paint()
      ..color = tickColor
      ..strokeWidth = 1;
    var t = (firstMs / minor).floor() * minor;
    while (t <= lastMs) {
      final x = leadPx + t * zoom - offset;
      final major = (t.round() % step) == 0;
      final top = major ? size.height * 0.45 : size.height * 0.7;
      canvas.drawLine(Offset(x, top), Offset(x, size.height), paint);
      if (major) {
        TextPainter(
          text: TextSpan(
            text: formatTimecode(
              t.round(),
              tenths: step < 1000,
              millis: step < 100,
            ),
            style: labelStyle,
          ),
          textDirection: textDirection,
        )
          ..layout()
          ..paint(canvas, Offset(x + 3, 0));
      }
      t += minor;
    }
  }

  @override
  bool shouldRepaint(RulerPainter old) =>
      old.offset != offset ||
      old.zoom != zoom ||
      old.leadPx != leadPx ||
      old.tickColor != tickColor ||
      old.labelStyle != labelStyle;
}

/// Pictures of a video or image clip side by side, decoded on demand for
/// the visible part only.
class FilmstripPainter extends CustomPainter {
  /// Creates the filmstrip painter for [clip] as drawn at [zoom].
  FilmstripPainter({
    required this.store,
    required this.clip,
    required this.zoom,
    required this.placeholder,
    this.viewport,
    this.contentLeft = 0,
  }) : super(repaint: Listenable.merge([store, viewport]));

  /// What part of the timeline is on screen; null draws everything.
  final TimelineViewport? viewport;

  /// Where the clip starts in timeline content pixels.
  final double contentLeft;

  /// Where pictures come from.
  final ThumbnailStore store;

  /// The clip drawn, possibly mid-trim.
  final Clip clip;

  /// Logical pixels per millisecond.
  final double zoom;

  /// Colour of a tile whose picture has not arrived yet.
  final Color placeholder;

  @override
  void paint(Canvas canvas, Size size) {
    final (visibleLeft, visibleRight) =
        viewport?.visibleIn(contentLeft, size.width) ?? (0.0, size.width);
    final tile = size.height * 9 / 16 < 24 ? 24.0 : size.height * 9 / 16;
    final path = filePathOf(clip.sourceUri);
    final step = niceStepMs(zoom, tile);
    final first = math.max(0, (visibleLeft / tile).floor());
    final last =
        math.min((size.width / tile).ceil(), (visibleRight / tile).ceil());
    final fill = Paint()..color = placeholder;
    canvas.drawRect(Offset.zero & size, fill);
    for (var i = first; i < last; i++) {
      final rect = Rect.fromLTWH(i * tile, 0, tile, size.height);
      final centreMs = clip.startMs + ((i + 0.5) * tile / zoom).round();
      final sourceMs = clip.kind == MediaKind.image
          ? 0
          : (sourceTimeAt(clip, centreMs) ~/ step) * step;
      final image = store.imageAt(path, sourceMs, toleranceMs: step ~/ 2);
      if (image == null) continue;
      _drawCover(canvas, image, rect);
    }
  }

  static void _drawCover(Canvas canvas, ui.Image image, Rect rect) {
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    final scale = math.max(rect.width / iw, rect.height / ih);
    final sw = rect.width / scale;
    final sh = rect.height / scale;
    final src = Rect.fromLTWH((iw - sw) / 2, (ih - sh) / 2, sw, sh);
    canvas.drawImageRect(
      image,
      src,
      rect,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(FilmstripPainter old) =>
      old.clip != clip || old.zoom != zoom || old.placeholder != placeholder;
}

/// The loudness of a sound clip as bars, for the visible part only.
class WaveformPainter extends CustomPainter {
  /// Creates the waveform painter.
  WaveformPainter({
    required this.peaks,
    required this.clip,
    required this.zoom,
    required this.color,
    this.viewport,
    this.contentLeft = 0,
  }) : super(repaint: viewport);

  /// What part of the timeline is on screen; null draws everything.
  final TimelineViewport? viewport;

  /// Where the clip starts in timeline content pixels.
  final double contentLeft;

  /// Peaks of the whole source, evenly spread over its duration.
  final List<double> peaks;

  /// The clip drawn, possibly mid-trim.
  final Clip clip;

  /// Logical pixels per millisecond.
  final double zoom;

  /// Colour of the bars.
  final Color color;

  static const double _bar = 2;
  static const double _gap = 1;

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty || clip.sourceDurationMs <= 0) return;
    final (visibleLeft, visibleRight) =
        viewport?.visibleIn(contentLeft, size.width) ?? (0.0, size.width);
    final paint = Paint()..color = color;
    final msPerPeak = clip.sourceDurationMs / peaks.length;
    final mid = size.height / 2;
    final firstBar = math.max(0, (visibleLeft / (_bar + _gap)).floor());
    var x = firstBar * (_bar + _gap);
    final end = math.min(size.width, visibleRight);
    while (x < end) {
      final fromMs = sourceTimeAt(clip, clip.startMs + (x / zoom).round());
      final toMs =
          sourceTimeAt(clip, clip.startMs + ((x + _bar + _gap) / zoom).round());
      final a = (math.min(fromMs, toMs) / msPerPeak).floor();
      final b = (math.max(fromMs, toMs) / msPerPeak).ceil();
      var peak = 0.0;
      for (var i = math.max(0, a); i <= math.min(peaks.length - 1, b); i++) {
        if (peaks[i] > peak) peak = peaks[i];
      }
      final h = math.max<double>(1, peak * size.height * 0.9);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, mid - h / 2, _bar, h),
          const Radius.circular(1),
        ),
        paint,
      );
      x += _bar + _gap;
    }
  }

  @override
  bool shouldRepaint(WaveformPainter old) =>
      !identical(old.peaks, peaks) ||
      old.clip != clip ||
      old.zoom != zoom ||
      old.color != color;
}
