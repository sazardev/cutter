import 'dart:async';
import 'dart:io';

import 'package:cutter/features/capture/domain/capture_ports.dart';
import 'package:cutter/features/capture/presentation/capture_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where a voice recording is.
enum VoicePhase {
  /// Not recording.
  idle,

  /// Recording.
  recording,

  /// The microphone is not allowed; nothing was recorded.
  denied,
}

/// What the voice recorder panel shows.
class VoiceState {
  /// Creates the state.
  const VoiceState({
    this.phase = VoicePhase.idle,
    this.elapsedMs = 0,
    this.startedAtMs = 0,
  });

  /// Where the recording is.
  final VoicePhase phase;

  /// How long it has been recording.
  final int elapsedMs;

  /// The playhead when the recording started: where the clip lands.
  final int startedAtMs;
}

/// A finished recording, ready to be imported at [atMs].
class VoiceTake {
  /// Creates a take.
  const VoiceTake({
    required this.path,
    required this.atMs,
    required this.interrupted,
  });

  /// The file with the recording.
  final String path;

  /// The playhead when the recording started.
  final int atMs;

  /// Whether the recording was cut short (the app left the front, say) and
  /// what was recorded so far was kept.
  final bool interrupted;
}

/// Records a voice into a file. It only deals with the microphone and the
/// file; placing the take on the timeline is the caller's job, so the same
/// controller serves the panel and an interruption.
class VoiceController extends AutoDisposeNotifier<VoiceState> {
  VoiceRecorder? _recorder;
  String? _path;
  Timer? _timer;
  final Stopwatch _clock = Stopwatch();

  @override
  VoiceState build() {
    ref.onDispose(() {
      _timer?.cancel();
      final recorder = _recorder;
      _recorder = null;
      if (recorder != null) unawaited(recorder.dispose());
    });
    return const VoiceState();
  }

  /// Starts recording; [playheadMs] is where the clip will land. Returns
  /// false when the microphone is not allowed or could not start.
  Future<bool> start(int playheadMs) async {
    if (state.phase == VoicePhase.recording) return true;
    final recorder = ref.read(voiceRecorderFactoryProvider)();
    try {
      if (!await recorder.requestPermission()) {
        await recorder.dispose();
        state = const VoiceState(phase: VoicePhase.denied);
        return false;
      }
      final path = await ref.read(voiceFilePathProvider)();
      await recorder.start(path);
      _recorder = recorder;
      _path = path;
    } on Object {
      await recorder.dispose();
      state = const VoiceState();
      return false;
    }
    _clock
      ..reset()
      ..start();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      state = VoiceState(
        phase: VoicePhase.recording,
        elapsedMs: _clock.elapsedMilliseconds,
        startedAtMs: playheadMs,
      );
    });
    state = VoiceState(phase: VoicePhase.recording, startedAtMs: playheadMs);
    return true;
  }

  /// Stops and returns the take, or null when nothing usable was recorded.
  /// [interrupted] marks a recording cut short, whose audio is kept.
  Future<VoiceTake?> stop({bool interrupted = false}) async {
    final recorder = _recorder;
    if (recorder == null) return null;
    final startedAt = state.startedAtMs;
    _timer?.cancel();
    _clock.stop();
    _recorder = null;
    state = const VoiceState();
    String? path;
    try {
      path = await recorder.stop() ?? _path;
    } on Object {
      // A recorder that fails to stop may still have written audio.
      path = _path;
    } finally {
      await recorder.dispose();
    }
    _path = null;
    if (path == null) return null;
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() == 0) return null;
    return VoiceTake(path: path, atMs: startedAt, interrupted: interrupted);
  }

  /// Forgets a denied state, e.g. after the user came back from settings.
  void clearDenied() {
    if (state.phase == VoicePhase.denied) state = const VoiceState();
  }
}

/// The voice recorder of the open editor.
final voiceControllerProvider =
    AutoDisposeNotifierProvider<VoiceController, VoiceState>(
  VoiceController.new,
);
