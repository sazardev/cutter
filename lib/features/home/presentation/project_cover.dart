import 'dart:async';
import 'dart:ui' as ui;

import 'package:cutter/core/engine/media_engine.dart';
import 'package:cutter/features/editor/data/engine_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Height, in physical pixels, of project covers.
const _coverHeightPx = 240;

/// The frame of the source at `(uri, ms)` that stands for a project in the
/// home list, decoded by the engine off the UI thread; null when the source
/// cannot be read.
final projectCoverProvider =
    FutureProvider.autoDispose.family<ui.Image?, (String, int)>((
  ref,
  key,
) async {
  final (uri, ms) = key;
  try {
    final thumbs = await ref.watch(mediaEngineProvider).thumbnails(
          filePathOf(uri),
          [ms],
          height: _coverHeightPx,
        );
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
  } on Object {
    // A moved or deleted file leaves the project with its plain poster.
    return null;
  }
});

/// The cover frame of a project filling its parent, or [placeholder] while
/// it loads or when there is none.
class ProjectCover extends ConsumerWidget {
  /// Creates the cover of the source [uri] at [ms].
  const ProjectCover({
    required this.uri,
    required this.ms,
    required this.placeholder,
    super.key,
  });

  /// The source whose frame is shown, or null for no cover.
  final String? uri;

  /// The moment of the source to show.
  final int ms;

  /// Shown until the picture is ready, and when there is none.
  final Widget placeholder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = uri;
    if (source == null) return placeholder;
    final image = ref.watch(projectCoverProvider((source, ms))).valueOrNull;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: image == null
          ? placeholder
          : SizedBox.expand(
              key: ValueKey(image),
              child: RawImage(image: image, fit: BoxFit.cover),
            ),
    );
  }
}
