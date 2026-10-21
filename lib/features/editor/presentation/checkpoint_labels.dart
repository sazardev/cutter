/// The names automatic restore points are saved under, in the language of
/// the screen; the page builds them, the controller only stores them.
class CheckpointLabels {
  /// Creates the labels.
  const CheckpointLabels({
    required this.start,
    required this.auto,
    required this.beforeRestore,
  });

  /// The point saved when a project opens for the first time.
  final String start;

  /// The point saved while editing, at `at`.
  final String Function(DateTime at) auto;

  /// The point saved before going back to the version named `name`.
  final String Function(String name) beforeRestore;
}
