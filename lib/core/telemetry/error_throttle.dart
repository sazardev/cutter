/// Lets the same error through once, then again only after [window].
///
/// A widget that throws while it builds throws again every frame, and
/// Crashlytics keeps only a few non-fatal reports per session: without this
/// one loop would push every other error out of the report.
class ErrorThrottle {
  /// Creates the throttle; [now] is the clock, for tests.
  ErrorThrottle({
    this.window = const Duration(minutes: 1),
    this.capacity = 64,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// How long a repeat of the same error stays quiet.
  final Duration window;

  /// How many different errors are remembered.
  final int capacity;

  final DateTime Function() _now;
  final Map<String, DateTime> _seen = {};

  /// Errors held back since the last one that went through.
  int suppressed = 0;

  /// Whether [error] raised at [stack] should be reported now.
  bool allow(Object error, StackTrace? stack) {
    final signature = _signature(error, stack);
    final now = _now();
    final last = _seen[signature];
    if (last != null && now.difference(last) < window) {
      suppressed++;
      return false;
    }
    _seen.remove(signature);
    _seen[signature] = now;
    while (_seen.length > capacity) {
      _seen.remove(_seen.keys.first);
    }
    return true;
  }

  /// The error's type and the first frame of its stack: what Crashlytics
  /// itself groups by, so two messages of one bug count as one.
  static String _signature(Object error, StackTrace? stack) {
    final frame = stack
        ?.toString()
        .split('\n')
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
    return '${error.runtimeType}|${frame ?? error}';
  }
}
