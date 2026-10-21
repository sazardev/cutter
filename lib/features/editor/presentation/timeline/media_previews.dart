import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:cutter/core/engine/media_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Height, in physical pixels, thumbnails are decoded at.
const thumbnailHeightPx = 96;

/// The most thumbnails kept in memory (about 20 KB each).
const _maxThumbnails = 600;

/// Pictures of sources at points in time, decoded by the engine in batches
/// and kept in a bounded cache. Listeners are told when new pictures arrive.
class ThumbnailStore extends ChangeNotifier {
  /// Creates a store reading from [_engine].
  ThumbnailStore(this._engine);

  final MediaEngine _engine;
  final LinkedHashMap<(String, int), ui.Image> _images = LinkedHashMap();
  // Wanted times by path, each with how far before it a picture may be.
  final Map<String, Map<int, int>> _wanted = {};
  final Set<String> _loading = {};
  final Set<String> _broken = {};
  // Times already asked for, so a picture the engine cannot make is not
  // asked for again on every repaint.
  final Set<(String, int)> _requested = {};
  bool _disposed = false;

  /// How many pictures are cached.
  int get count => _images.length;

  /// The picture of [path] at [timeMs], or the closest one already decoded,
  /// or null. A missing picture is requested; it may come from up to
  /// [toleranceMs] earlier.
  ui.Image? imageAt(String path, int timeMs, {int toleranceMs = 0}) {
    final exact = _images.remove((path, timeMs));
    if (exact != null) {
      _images[(path, timeMs)] = exact;
      return exact;
    }
    if (!_broken.contains(path) && _requested.add((path, timeMs))) {
      (_wanted[path] ??= <int, int>{})[timeMs] = toleranceMs;
      scheduleMicrotask(() => _load(path));
    }
    ui.Image? closest;
    var distance = 1 << 62;
    for (final entry in _images.entries) {
      if (entry.key.$1 != path) continue;
      final d = (entry.key.$2 - timeMs).abs();
      if (d < distance) {
        distance = d;
        closest = entry.value;
      }
    }
    return closest;
  }

  Future<void> _load(String path) async {
    if (_disposed || _loading.contains(path)) return;
    final wanted = _wanted.remove(path);
    if (wanted == null || wanted.isEmpty) return;
    final times = [
      for (final t in wanted.keys)
        if (!_images.containsKey((path, t))) t,
    ];
    if (times.isEmpty) return;
    // One batch shares the strictest tolerance asked for.
    final tolerance = wanted.values.reduce((a, b) => a < b ? a : b);
    _loading.add(path);
    try {
      final thumbs = await _engine.thumbnails(
        path,
        times,
        height: thumbnailHeightPx,
        toleranceMs: tolerance,
      );
      for (final thumb in thumbs) {
        final image = await _decode(thumb);
        if (_disposed) {
          image.dispose();
          return;
        }
        _images[(path, thumb.timeMs)] = image;
      }
      while (_images.length > _maxThumbnails) {
        final oldest = _images.keys.first;
        _images.remove(oldest)?.dispose();
        _requested.remove(oldest);
      }
      notifyListeners();
    } on Object {
      _broken.add(path);
    } finally {
      _loading.remove(path);
      if (!_disposed && (_wanted[path]?.isNotEmpty ?? false)) {
        unawaited(_load(path));
      }
    }
  }

  static Future<ui.Image> _decode(Thumbnail thumb) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      thumb.rgba,
      thumb.width,
      thumb.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    super.dispose();
  }
}

/// The thumbnails of the open editor.
final thumbnailStoreProvider =
    ChangeNotifierProvider.autoDispose<ThumbnailStore>(
  (ref) => ThumbnailStore(ref.watch(mediaEngineProvider)),
);

/// Peaks of a sound file, about 40 per second, scaled so the loudest is 1:
/// a quiet recording is as readable on the timeline as a loud one.
final waveformProvider = FutureProvider.autoDispose
    .family<List<double>, (String path, int durationMs)>((ref, key) async {
  final buckets = (key.$2 / 25).round().clamp(64, 8000);
  final peaks = await ref.watch(mediaEngineProvider).waveform(key.$1, buckets);
  final loudest = peaks.fold<double>(0, (a, b) => b > a ? b : a);
  if (loudest <= 0) return peaks;
  return [for (final peak in peaks) peak / loudest];
});
