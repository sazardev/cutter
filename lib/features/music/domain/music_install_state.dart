/// Why a pack could not be installed.
enum MusicFailure {
  /// The download did not finish.
  network,

  /// The zip is damaged, the wrong size, or does not hold what it says.
  corrupt,

  /// The files could not be written.
  storage,
}

/// Where a pack stands on this device.
sealed class PackState {
  const PackState();
}

/// Not on the device.
final class PackAvailable extends PackState {
  /// Creates the state.
  const PackAvailable();
}

/// Being downloaded; [progress] is 0 to 1, or null when the size is unknown.
final class PackDownloading extends PackState {
  /// Creates the state.
  const PackDownloading(this.progress);

  /// Fraction downloaded.
  final double? progress;
}

/// Downloaded and being unpacked.
final class PackUnpacking extends PackState {
  /// Creates the state.
  const PackUnpacking();
}

/// On the device, ready offline.
final class PackInstalled extends PackState {
  /// Creates the state.
  const PackInstalled();
}

/// The last install did not work.
final class PackFailed extends PackState {
  /// Creates the state.
  const PackFailed(this.failure);

  /// Why.
  final MusicFailure failure;
}
