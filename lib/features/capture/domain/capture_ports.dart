/// The camera, as the editor needs it: a photo or a video recorded with the
/// system camera, handed back as a file path.
abstract interface class CameraCapture {
  /// Takes a photo. Returns its path, or null when the user cancelled.
  /// Throws [CameraDenied] when the camera is not allowed.
  Future<String?> photo();

  /// Records a video. Returns its path, or null when the user cancelled.
  /// Throws [CameraDenied] when the camera is not allowed.
  Future<String?> video();

  /// A capture the system finished while the app was away (Android may end
  /// the app while the camera is open), or null.
  Future<String?> lostCapture();
}

/// The camera is not allowed for the app.
class CameraDenied implements Exception {
  /// Creates the error.
  const CameraDenied();
}

/// The microphone, as the editor needs it: record a voice into a file.
abstract interface class VoiceRecorder {
  /// Asks for the microphone if needed; true when recording is allowed.
  Future<bool> requestPermission();

  /// Starts recording into the file at [path].
  Future<void> start(String path);

  /// Stops and returns the path of the file, or null when nothing was
  /// recorded.
  Future<String?> stop();

  /// Whether a recording is running.
  Future<bool> get isRecording;

  /// Releases the recorder.
  Future<void> dispose();
}
