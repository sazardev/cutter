import 'dart:async';
import 'dart:io';

import 'package:cutter/core/engine/media_engine.dart';
import 'package:cutter/core/telemetry/telemetry.dart';

/// A panic the Rust engine caught on one of its own threads.
///
/// Those threads die without the Dart side hearing of it, so the engine
/// writes the panic to its log and [EngineWatch] turns it into a report.
class EnginePanic implements Exception {
  /// Creates the error from the engine's log [line].
  const EnginePanic(this.line);

  /// The log line, with the time, the place and the message of the panic.
  final String line;

  @override
  String toString() => 'EnginePanic: $line';
}

/// Every few seconds, copies what the engine knows into the crash reports:
/// its counters and the process memory as custom keys (they ride along with
/// a native crash too), its error lines as breadcrumbs, and each panic as a
/// non-fatal error. One cheap synchronous call per tick, never during a
/// frame-critical path.
class EngineWatch {
  /// Creates the watch over [engine], reporting to [telemetry].
  EngineWatch({
    required this.engine,
    required this.telemetry,
    this.interval = const Duration(seconds: 10),
    int Function()? residentBytes,
  }) : _residentBytes = residentBytes ?? (() => ProcessInfo.currentRss);

  /// The engine to read.
  final MediaEngine engine;

  /// Where the reports go.
  final Telemetry telemetry;

  /// Time between two readings.
  final Duration interval;

  final int Function() _residentBytes;
  final Map<String, String> _keys = {};
  Timer? _timer;
  String? _lastLine;

  /// Starts reading; does nothing when telemetry is off.
  void start() {
    if (!telemetry.enabled || _timer != null) return;
    _timer = Timer.periodic(interval, (_) => poll());
  }

  /// Stops reading.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// One reading.
  void poll() {
    try {
      final stats = engine.diagnostics();
      _set('engine_late_frames', stats.lateFrames);
      _set('engine_frames', stats.framesRendered);
      _set('engine_cache_mb', stats.cacheBytes ~/ BigInt.from(1 << 20));
      _set('engine_preview_scale', stats.previewScale.toStringAsFixed(2));
      _set('engine_video_decoders', stats.openVideoDecoders);
      _set('engine_audio_decoders', stats.openAudioDecoders);
      _set('process_rss_mb', _residentBytes() >> 20);
      _report(stats.log);
    } on Object {
      // The watch must never be the reason the app fails.
    }
  }

  void _set(String name, Object value) {
    final text = value.toString();
    if (_keys[name] == text) return;
    _keys[name] = text;
    telemetry.setKey(name, text);
  }

  void _report(List<String> lines) {
    final last = _lastLine;
    final from = last == null ? -1 : lines.lastIndexOf(last);
    for (final line in lines.skip(from + 1)) {
      final level = _level.firstMatch(line)?.group(1);
      if (level != 'E') continue;
      telemetry.log('engine: $line');
      if (line.contains(' panicked at ')) {
        unawaited(
          telemetry.recordError(
            EnginePanic(line),
            StackTrace.current,
            reason: 'Rust panic',
            keys: {'stage': 'engine_panic'},
          ),
        );
      }
    }
    if (lines.isNotEmpty) _lastLine = lines.last;
  }

  /// `00:00:00.000 E message`: the letter after the time is the level.
  static final RegExp _level = RegExp(r'^\S+ ([IWE]) ');
}
