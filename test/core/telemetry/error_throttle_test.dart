import 'package:cutter/core/telemetry/error_throttle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime clock;
  late ErrorThrottle throttle;
  final stack =
      StackTrace.fromString('#0      build (package:cutter/a.dart:1:1)');
  final other =
      StackTrace.fromString('#0      paint (package:cutter/b.dart:2:2)');

  setUp(() {
    clock = DateTime(2026, 10, 22);
    throttle = ErrorThrottle(now: () => clock);
  });

  test('lets an error through once and holds back its repeats', () {
    expect(throttle.allow(StateError('a'), stack), isTrue);
    expect(throttle.allow(StateError('b'), stack), isFalse);
    expect(throttle.allow(StateError('c'), stack), isFalse);
    expect(throttle.suppressed, 2);
  });

  test('tells errors apart by type and by where they were thrown', () {
    expect(throttle.allow(StateError('a'), stack), isTrue);
    expect(throttle.allow(ArgumentError('a'), stack), isTrue);
    expect(throttle.allow(StateError('a'), other), isTrue);
  });

  test('lets the error through again after the window', () {
    expect(throttle.allow(StateError('a'), stack), isTrue);
    clock = clock.add(const Duration(seconds: 61));
    expect(throttle.allow(StateError('a'), stack), isTrue);
  });

  test('without a stack it tells errors by message', () {
    expect(throttle.allow(StateError('a'), null), isTrue);
    expect(throttle.allow(StateError('a'), null), isFalse);
    expect(throttle.allow(StateError('b'), null), isTrue);
  });

  test('forgets the oldest errors past its capacity', () {
    final small = ErrorThrottle(capacity: 2, now: () => clock);
    expect(small.allow(StateError('a'), null), isTrue);
    expect(small.allow(StateError('b'), null), isTrue);
    expect(small.allow(StateError('c'), null), isTrue);
    expect(small.allow(StateError('a'), null), isTrue);
  });
}
