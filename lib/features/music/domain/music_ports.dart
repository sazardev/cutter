import 'package:cutter/features/music/domain/music_install_state.dart';
import 'package:cutter/features/music/domain/music_pack.dart';

/// The list of packs the app can offer.
// ignore: one_member_abstracts
abstract interface class MusicCatalog {
  /// Loads the catalog from the network, keeping a copy for offline use.
  /// Returns that copy when the network fails; null when there is none.
  Future<List<MusicPack>?> load();
}

/// The packs on the device.
abstract interface class MusicPackStore {
  /// The packs installed, found on disk, so it works without a network.
  Future<List<InstalledPack>> installed();

  /// Downloads and unpacks [pack]. [onProgress] gets the fraction downloaded
  /// (null when the size is unknown); [onUnpacking] is called when the
  /// download is done. Throws [MusicInstallException] when it fails; nothing
  /// of a failed install stays on disk and an older copy is kept.
  Future<InstalledPack> install(
    MusicPack pack, {
    required void Function(double? progress) onProgress,
    required void Function() onUnpacking,
  });

  /// Deletes the installed pack with [id].
  Future<void> remove(String id);
}

/// An install that did not work.
class MusicInstallException implements Exception {
  /// Creates the exception.
  const MusicInstallException(this.failure, [this.cause]);

  /// What went wrong.
  final MusicFailure failure;

  /// The underlying error, for logs.
  final Object? cause;

  @override
  String toString() => 'MusicInstallException($failure, $cause)';
}
