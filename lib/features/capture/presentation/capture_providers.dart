import 'dart:io';

import 'package:cutter/features/capture/data/image_picker_camera.dart';
import 'package:cutter/features/capture/data/record_voice_recorder.dart';
import 'package:cutter/features/capture/domain/capture_ports.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// The system camera. Tests replace it.
final cameraCaptureProvider = Provider<CameraCapture>(
  (ref) => ImagePickerCamera(),
);

/// Creates a recorder for one voice recording; it is disposed when the
/// recording is over. Tests replace it.
final voiceRecorderFactoryProvider = Provider<VoiceRecorder Function()>(
  (ref) => RecordVoiceRecorder.new,
);

/// Where a new voice recording is written: a temporary file the media
/// library then takes into the app. Tests replace it.
final voiceFilePathProvider = Provider<Future<String> Function()>(
  (ref) => () async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '${dir.path}${Platform.pathSeparator}voice_$stamp.m4a';
  },
);

/// Whether this device can capture: phones and tablets have the camera and
/// microphone the capture tools use, so only there does the editor show the
/// Capture tool. Tests replace it.
final captureAvailableProvider = Provider<bool>(
  (ref) => Platform.isAndroid || Platform.isIOS,
);
