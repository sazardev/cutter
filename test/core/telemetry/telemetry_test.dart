import 'package:cutter/core/telemetry/telemetry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the no-op reporter accepts every call and sends nothing', () async {
    const telemetry = NoopTelemetry();

    expect(telemetry.enabled, isFalse);
    expect(telemetry.installId, isNull);

    telemetry
      ..log('hello')
      ..setKey('stage', 'test');
    await telemetry.recordError(StateError('boom'), StackTrace.current);
    await telemetry.event('test_event', parameters: {'one': 1});
    final trace = telemetry.startTrace('test_trace')
      ..setAttribute('result', 'done')
      ..setMetric('duration_ms', 10);
    await trace.stop();
    await telemetry.identify('install-id');
  });

  test('the provider defaults to the no-op reporter', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final reporter = container.read(telemetryProvider);

    expect(reporter, isA<NoopTelemetry>());
    expect(reporter.enabled, isFalse);
  });
}
