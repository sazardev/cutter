import 'dart:async';

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
  /// download is done. Throws [MusicInstallException] when it fails, and
  /// [MusicTransferStopped] when [control] paused or cancelled it. A failed
  /// install leaves no files except a partial download that can be resumed,
  /// and an older copy is kept.
  Future<InstalledPack> install(
    MusicPack pack, {
    required void Function(double? progress) onProgress,
    required void Function() onUnpacking,
    required TransferControl control,
  });

  /// Bytes already downloaded of packs whose download was paused or cut, by
  /// pack id; installing again goes on from there.
  Future<Map<String, int>> partials();

  /// Throws away what was downloaded of the pack with [id].
  Future<void> discardPartial(String id);

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

/// Lets the caller pause or cancel a download in progress.
class TransferControl {
  final Completer<void> _stopped = Completer<void>();
  bool _cancelled = false;

  /// Completes when a pause or a cancel is asked for.
  Future<void> get whenStopped => _stopped.future;

  /// Whether a pause or a cancel was asked for.
  bool get stopRequested => _stopped.isCompleted;

  /// Whether the stop was a cancel (otherwise it is a pause).
  bool get cancelled => _cancelled;

  /// Asks the download to stop and keep what it has.
  void pause() {
    if (!_stopped.isCompleted) _stopped.complete();
  }

  /// Asks the download to stop and throw what it has away.
  void cancel() {
    _cancelled = true;
    if (!_stopped.isCompleted) _stopped.complete();
  }
}

/// A download that was stopped on purpose.
class MusicTransferStopped implements Exception {
  /// Creates the exception.
  const MusicTransferStopped({required this.paused});

  /// Paused (the partial file is kept) rather than cancelled.
  final bool paused;

  @override
  String toString() => 'MusicTransferStopped(paused: $paused)';
}
