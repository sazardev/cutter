import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';

/// Whether the app may save videos to the gallery. Tests replace it.
final galleryAccessProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    return await Gal.hasAccess(toAlbum: true);
  } on Object {
    return false;
  }
});

/// Asks the system for gallery access and returns whether it was granted.
final requestGalleryAccessProvider = Provider<Future<bool> Function()>(
  (ref) => () async {
    try {
      return await Gal.requestAccess(toAlbum: true);
    } on Object {
      return false;
    }
  },
);

/// Opens the system settings page of the app, where permissions are
/// changed. Tests replace it.
final openSystemSettingsProvider = Provider<Future<bool> Function()>(
  (ref) => openAppSettings,
);
