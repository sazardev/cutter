import 'package:cutter/features/capture/domain/capture_ports.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// The system camera through `image_picker`: its own camera screen, so no
/// camera permission is declared by the app on Android; iOS asks when the
/// camera opens.
class ImagePickerCamera implements CameraCapture {
  /// Creates the camera over [_picker].
  ImagePickerCamera([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<String?> photo() => _guard(
        () async => (await _picker.pickImage(source: ImageSource.camera))?.path,
      );

  @override
  Future<String?> video() => _guard(
        () async => (await _picker.pickVideo(source: ImageSource.camera))?.path,
      );

  @override
  Future<String?> lostCapture() async {
    try {
      final lost = await _picker.retrieveLostData();
      if (lost.isEmpty) return null;
      return lost.file?.path;
    } on Object {
      return null;
    }
  }

  Future<String?> _guard(Future<String?> Function() capture) async {
    try {
      return await capture();
    } on PlatformException catch (error) {
      if (error.code == 'camera_access_denied' ||
          error.code == 'camera_access_restricted') {
        throw const CameraDenied();
      }
      rethrow;
    }
  }
}
