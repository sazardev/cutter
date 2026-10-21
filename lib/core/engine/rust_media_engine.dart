import 'dart:async';

import 'package:cutter/core/engine/bridge/api/engine.dart' as rust;
import 'package:cutter/core/engine/bridge/frb_generated.dart';
import 'package:cutter/core/engine/media_engine.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' show Int64List;
import 'package:irondash_engine_context/irondash_engine_context.dart';

/// The media engine backed by the Rust library through Flutter Rust Bridge.
class RustMediaEngine implements MediaEngine {
  RustMediaEngine._();

  /// Loads the native library; call once before `runApp`.
  static Future<RustMediaEngine> load() async {
    await RustLib.init();
    return RustMediaEngine._();
  }

  @override
  Future<PreviewSession> openPreview() async {
    final handle = await EngineContext.instance.getEngineHandle();
    final player = await rust.PreviewPlayer.create(engineHandle: handle);
    return _RustPreviewSession(player);
  }

  @override
  Future<MediaInfo> probe(String path) => rust.probeMedia(path: path);

  @override
  Future<List<Thumbnail>> thumbnails(
    String path,
    List<int> timesMs, {
    required int height,
    int toleranceMs = 0,
  }) {
    return rust.thumbnails(
      path: path,
      timesMs: Int64List.fromList(timesMs),
      height: height,
      toleranceMs: toleranceMs,
    );
  }

  @override
  Future<List<double>> waveform(String path, int buckets) async {
    final peaks = await rust.waveform(path: path, buckets: buckets);
    return [for (final peak in peaks) peak];
  }

  @override
  EngineDiagnostics diagnostics() => rust.engineDiagnostics();

  @override
  Future<SuggestedAdjustments> suggestAdjustments(
    String path, {
    required int fromMs,
    required int toMs,
  }) {
    return rust.suggestAdjustments(path: path, fromMs: fromMs, toMs: toMs);
  }

  @override
  ExportTask export(Timeline timeline, ExportSettings settings, String path) {
    final job = rust.ExportJob();
    final events = job
        .run(timeline: timeline, settings: settings, path: path)
        .asBroadcastStream();
    return _RustExportTask(job, events);
  }
}

class _RustPreviewSession implements PreviewSession {
  _RustPreviewSession(this._player)
      : states = _player.events().asBroadcastStream();

  final rust.PreviewPlayer _player;

  @override
  final Stream<PlaybackState> states;

  @override
  int get textureId => _player.textureId;

  @override
  void setTimeline(Timeline timeline) =>
      _player.setTimeline(timeline: timeline);

  @override
  void setBounds(int width, int height) =>
      _player.setBounds(width: width, height: height);

  @override
  void play() => _player.play();

  @override
  void pause() => _player.pause();

  @override
  void seek(int positionMs) => _player.seek(positionMs: positionMs);

  @override
  void dispose() => _player.dispose();
}

class _RustExportTask implements ExportTask {
  _RustExportTask(this._job, this.events);

  final rust.ExportJob _job;

  @override
  final Stream<ExportEvent> events;

  @override
  void cancel() => _job.cancel();
}
