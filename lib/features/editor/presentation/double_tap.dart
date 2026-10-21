/// How close in time two taps on the same clip must be to count as a double
/// tap.
const Duration doubleTapWindow = Duration(milliseconds: 320);

/// Tells a second tap on the same clip from a first one, without delaying
/// the first: the tap is acted on at once and this only remembers it.
class DoubleTap {
  String? _id;
  DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);

  /// Registers a tap on [id] at [now]; true when it is the second of a
  /// double tap.
  bool tap(String id, {DateTime? now}) {
    final time = now ?? DateTime.now();
    final second = _id == id && time.difference(_at) <= doubleTapWindow;
    _id = second ? null : id;
    _at = time;
    return second;
  }
}
