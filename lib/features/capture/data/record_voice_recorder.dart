import 'package:cutter/features/capture/domain/capture_ports.dart';
import 'package:record/record.dart';

/// The microphone through the `record` package: AAC in an `.m4a` file, which
/// the engine plays like any imported sound.
class RecordVoiceRecorder implements VoiceRecorder {
  /// Creates the recorder over [_recorder].
  RecordVoiceRecorder([AudioRecorder? recorder])
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> requestPermission() => _recorder.hasPermission();

  @override
  Future<void> start(String path) =>
      _recorder.start(const RecordConfig(), path: path);

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<bool> get isRecording => _recorder.isRecording();

  @override
  Future<void> dispose() => _recorder.dispose();
}
