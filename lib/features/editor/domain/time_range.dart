// All fields are final, so the class is immutable; the `meta` package that
// provides `@immutable` is not a declared dependency of the domain.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// A span on the project timeline in integer milliseconds.
class TimeRange {
  /// Creates a span starting at [startMs] and lasting [durationMs].
  const TimeRange(this.startMs, this.durationMs);

  /// Start of the span on the project timeline, in milliseconds.
  final int startMs;

  /// Length of the span, in milliseconds.
  final int durationMs;

  /// End of the span, in milliseconds (exclusive).
  int get endMs => startMs + durationMs;

  /// True when the spans share time; ranges that only touch do not overlap.
  bool overlaps(TimeRange other) =>
      startMs < other.endMs && other.startMs < endMs;

  /// True when [ms] lies strictly between the start and the end.
  bool containsStrictly(int ms) => startMs < ms && ms < endMs;

  @override
  bool operator ==(Object other) =>
      other is TimeRange &&
      other.startMs == startMs &&
      other.durationMs == durationMs;

  @override
  int get hashCode => Object.hash(startMs, durationMs);

  @override
  String toString() => 'TimeRange($startMs, $durationMs)';
}
