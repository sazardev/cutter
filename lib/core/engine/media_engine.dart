import 'package:cutter/core/engine/bridge/api/types.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:cutter/core/engine/bridge/api/types.dart';

/// A live preview drawn by the engine into a Flutter texture.
abstract interface class PreviewSession {
  /// The id to give a `Texture` widget.
  int get textureId;

  /// The position while playing, and after every seek or edit.
  Stream<PlaybackState> get states;

  /// Replaces what the preview shows; cheap enough to call on every edit.
  void setTimeline(Timeline timeline);

  /// The box, in physical pixels, the preview is shown in.
  void setBounds(int width, int height);

  /// Starts playing from the current position.
  void play();

  /// Stops playing and keeps the position.
  void pause();

  /// Moves to [positionMs] and draws that instant.
  void seek(int positionMs);

  /// Releases the texture and the engine threads.
  void dispose();
}

/// A running export.
abstract interface class ExportTask {
  /// Progress, ending with a `done`, `failed` or `cancelled` stage.
  Stream<ExportEvent> get events;

  /// Asks the export to stop; the partial file is removed.
  void cancel();
}

/// Everything Flutter asks of the Rust media engine. The UI only talks to
/// this interface, so widget tests run without the native library.
abstract interface class MediaEngine {
  /// Starts a preview session.
  Future<PreviewSession> openPreview();

  /// Describes the file at [path]; throws when it is not playable media.
  Future<MediaInfo> probe(String path);

  /// Pictures of [path] near [timesMs], [height] physical pixels tall; each
  /// may be up to [toleranceMs] before its time, which lets a zoomed-out
  /// strip use keyframes instead of decoding to the exact frame.
  Future<List<Thumbnail>> thumbnails(
    String path,
    List<int> timesMs, {
    required int height,
    int toleranceMs = 0,
  });

  /// Peak loudness of [path] in [buckets] slices, each 0 to 1.
  Future<List<double>> waveform(String path, int buckets);

  /// Renders [timeline] into an MP4 file at [path].
  ExportTask export(Timeline timeline, ExportSettings settings, String path);

  /// Counters and recent log lines of the engine.
  EngineDiagnostics diagnostics();

  /// Adjustments that balance the picture of [path] between [fromMs] and
  /// [toMs] of its source.
  Future<SuggestedAdjustments> suggestAdjustments(
    String path, {
    required int fromMs,
    required int toMs,
  });
}

/// The engine. `main` overrides it once the native library is loaded;
/// reading it before that is a programmer error.
final mediaEngineProvider = Provider<MediaEngine>(
  (ref) => throw StateError(
    'mediaEngineProvider must be overridden with the loaded engine.',
  ),
);
