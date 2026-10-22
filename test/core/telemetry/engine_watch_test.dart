import 'package:cutter/core/engine/bridge/api/types.dart';
import 'package:cutter/core/telemetry/engine_watch.dart';
import 'package:cutter/core/telemetry/telemetry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../engine/fake_media_engine.dart';

class _Engine extends FakeMediaEngine {
  List<String> log = [];
  int late = 0;

  @override
  EngineDiagnostics diagnostics() => EngineDiagnostics(
        framesRendered: BigInt.from(100),
        avgRenderMs: 2,
        maxRenderMs: 5,
        lateFrames: BigInt.from(late),
        openVideoDecoders: 2,
        openAudioDecoders: 1,
        cacheBytes: BigInt.from(3 << 20),
        log: log,
        previewScale: 0.5,
      );
}

class _Recorder implements Telemetry {
  final logs = <String>[];
  final keys = <String, Object>{};
  final errors = <Object>[];

  @override
  bool get enabled => true;

  @override
  String? get installId => null;

  @override
  void log(String message) => logs.add(message);

  @override
  void setKey(String name, Object value) => keys[name] = value;

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
    Map<String, Object>? keys,
  }) async =>
      errors.add(error);

  @override
  Future<void> event(String name, {Map<String, Object>? parameters}) async {}

  @override
  TelemetryTrace startTrace(String name, {Map<String, String>? attributes}) =>
      const NoopTrace();

  @override
  Future<void> identify(String installId) async {}
}

void main() {
  late _Engine engine;
  late _Recorder telemetry;
  late EngineWatch watch;

  setUp(() {
    engine = _Engine();
    telemetry = _Recorder();
    watch = EngineWatch(
      engine: engine,
      telemetry: telemetry,
      residentBytes: () => 300 << 20,
    );
  });

  test('copies the counters and the memory into custom keys', () {
    engine.late = 4;
    watch.poll();

    expect(telemetry.keys['engine_late_frames'], '4');
    expect(telemetry.keys['engine_cache_mb'], '3');
    expect(telemetry.keys['engine_preview_scale'], '0.50');
    expect(telemetry.keys['engine_video_decoders'], '2');
    expect(telemetry.keys['process_rss_mb'], '300');
  });

  test('only sends a key again when its value changed', () {
    watch.poll();
    telemetry.keys.clear();
    watch.poll();
    expect(telemetry.keys, isEmpty);

    engine.late = 9;
    watch.poll();
    expect(telemetry.keys.keys, ['engine_late_frames']);
  });

  test('leaves error lines as breadcrumbs, once, and skips the rest', () {
    engine.log = [
      '00:00:01.000 I engine ready',
      '00:00:02.000 W probe /x: slow',
      '00:00:03.000 E decode failed: eof',
    ];
    watch
      ..poll()
      ..poll();

    expect(telemetry.logs, ['engine: 00:00:03.000 E decode failed: eof']);

    engine.log = [...engine.log, '00:00:04.000 E export failed: disk'];
    watch.poll();
    expect(telemetry.logs.last, 'engine: 00:00:04.000 E export failed: disk');
    expect(telemetry.logs, hasLength(2));
  });

  test('a panic becomes a non-fatal error', () {
    engine.log = [
      "00:00:05.000 E thread 'preview' panicked at src/playback/mod.rs:9: no",
    ];
    watch.poll();

    expect(telemetry.errors.single, isA<EnginePanic>());
  });

  test('a failing engine never throws out of the watch', () {
    final broken = EngineWatch(
      engine: _Throwing(),
      telemetry: telemetry,
      residentBytes: () => 0,
    );
    expect(broken.poll, returnsNormally);
  });
}

class _Throwing extends FakeMediaEngine {
  @override
  EngineDiagnostics diagnostics() => throw StateError('engine gone');
}
