import 'dart:async';
import 'dart:typed_data';

import 'package:cutter/core/engine/media_engine.dart';

/// A preview that records what it was told, for widget and controller tests.
class FakePreviewSession implements PreviewSession {
  /// The timelines received, latest last.
  final List<Timeline> timelines = [];

  /// Positions sought, latest last.
  final List<int> seeks = [];

  /// Whether play was called last (rather than pause).
  bool playing = false;

  /// Whether dispose was called.
  bool disposed = false;

  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();

  /// Sends a playback update as the engine would.
  void emit(int positionMs, {bool playing = false}) =>
      _states.add(PlaybackState(positionMs: positionMs, playing: playing));

  @override
  int get textureId => 7;

  @override
  Stream<PlaybackState> get states => _states.stream;

  @override
  void setTimeline(Timeline timeline) => timelines.add(timeline);

  @override
  void setBounds(int width, int height) {}

  @override
  void play() => playing = true;

  @override
  void pause() => playing = false;

  @override
  void seek(int positionMs) => seeks.add(positionMs);

  @override
  void dispose() {
    disposed = true;
    unawaited(_states.close());
  }
}

/// An engine that knows media files by path, without native code.
class FakeMediaEngine implements MediaEngine {
  /// Creates the engine; [media] describes the files it can read.
  FakeMediaEngine({Map<String, MediaInfo>? media}) : media = media ?? {};

  /// What [probe] answers, by path; other paths fail.
  final Map<String, MediaInfo> media;

  /// The preview opened last.
  FakePreviewSession? session;

  @override
  Future<PreviewSession> openPreview() async => session = FakePreviewSession();

  @override
  Future<MediaInfo> probe(String path) async {
    final info = media[path];
    if (info == null) throw StateError('unreadable $path');
    return info;
  }

  @override
  Future<List<Thumbnail>> thumbnails(
    String path,
    List<int> timesMs, {
    required int height,
    int toleranceMs = 0,
  }) async {
    return [
      for (final t in timesMs)
        Thumbnail(
          timeMs: t,
          width: 2,
          height: 2,
          rgba: Uint8List(16),
        ),
    ];
  }

  @override
  Future<List<double>> waveform(String path, int buckets) async =>
      List.filled(buckets, 0.5);

  @override
  ExportTask export(Timeline timeline, ExportSettings settings, String path) =>
      throw UnimplementedError();

  @override
  EngineDiagnostics diagnostics() => EngineDiagnostics(
        framesRendered: BigInt.from(10),
        avgRenderMs: 2,
        maxRenderMs: 5,
        lateFrames: BigInt.zero,
        openVideoDecoders: 1,
        openAudioDecoders: 0,
        cacheBytes: BigInt.zero,
        log: ['00:00:00.000 I engine ready'],
        previewScale: 1,
      );

  @override
  Future<SuggestedAdjustments> suggestAdjustments(
    String path, {
    required int fromMs,
    required int toMs,
  }) async =>
      const SuggestedAdjustments(brightness: 0.2, contrast: 0.1, saturation: 0);
}

/// A video file as the engine would describe it.
const MediaInfo fakeVideo = MediaInfo(
  kind: EngineMediaKind.video,
  durationMs: 4000,
  width: 1920,
  height: 1080,
  hasAudio: true,
  frameRate: 30,
  rotation: 0,
);

/// A sound file as the engine would describe it.
const MediaInfo fakeSound = MediaInfo(
  kind: EngineMediaKind.audio,
  durationMs: 2000,
  width: 0,
  height: 0,
  hasAudio: true,
  frameRate: 0,
  rotation: 0,
);
