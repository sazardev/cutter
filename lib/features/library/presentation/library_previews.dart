import 'dart:async';
import 'dart:ui' as ui;

import 'package:cutter/core/engine/media_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Height, in physical pixels, of library thumbnails.
const _posterHeight = 240;

/// A poster frame of the video at `path`, one second in (or its first
/// frame), cached while the library is on screen.
final videoPosterProvider =
    FutureProvider.autoDispose.family<ui.Image?, String>((ref, path) async {
  final engine = ref.watch(mediaEngineProvider);
  final thumbs =
      await engine.thumbnails(path, const [1000], height: _posterHeight);
  if (thumbs.isEmpty) return null;
  final thumb = thumbs.first;
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    thumb.rgba,
    thumb.width,
    thumb.height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  final image = await completer.future;
  ref.onDispose(image.dispose);
  return image;
});
