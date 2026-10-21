const int _msPerSecond = 1000;
const int _secondsPerMinute = 60;

/// Formats [ms] as `mm:ss.mmm` for precise labels.
String formatTimelineTime(int ms) {
  final clamped = ms < 0 ? 0 : ms;
  final minutes = clamped ~/ (_msPerSecond * _secondsPerMinute);
  final seconds = (clamped ~/ _msPerSecond) % _secondsPerMinute;
  final millis = clamped % _msPerSecond;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}.'
      '${millis.toString().padLeft(3, '0')}';
}

/// Formats [ms] as `m:ss`, `m:ss.d` when [tenths] is set, or `m:ss.mmm` when
/// [millis] is set, for the transport and the ruler.
String formatTimecode(int ms, {bool tenths = false, bool millis = false}) {
  final clamped = ms < 0 ? 0 : ms;
  final minutes = clamped ~/ (_msPerSecond * _secondsPerMinute);
  final seconds = (clamped ~/ _msPerSecond) % _secondsPerMinute;
  final base = '$minutes:${seconds.toString().padLeft(2, '0')}';
  if (millis) {
    return '$base.${(clamped % _msPerSecond).toString().padLeft(3, '0')}';
  }
  if (!tenths) return base;
  return '$base.${(clamped % _msPerSecond) ~/ 100}';
}
