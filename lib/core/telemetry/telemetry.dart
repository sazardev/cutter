import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One timed operation shown in Firebase Performance.
abstract interface class TelemetryTrace {
  /// Adds a string attribute to the trace.
  void setAttribute(String name, String value);

  /// Sets an integer metric on the trace.
  void setMetric(String name, int value);

  /// Stops the trace and sends it.
  Future<void> stop();
}

/// What the app reports about crashes, usage and performance.
///
/// Every call is safe without Firebase: tests and the desktop use
/// [NoopTelemetry], and a device without the configuration falls back to it.
abstract interface class Telemetry {
  /// Whether reports leave the device.
  bool get enabled;

  /// A random identifier for this install, set once the database is open.
  String? get installId;

  /// Leaves a breadcrumb that shows up in the next crash report.
  void log(String message);

  /// Adds a value to the state of the next crash report.
  void setKey(String name, Object value);

  /// Records a non-fatal or fatal error.
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
    Map<String, Object>? keys,
  });

  /// Records a usage event.
  Future<void> event(String name, {Map<String, Object>? parameters});

  /// Starts a performance trace.
  TelemetryTrace startTrace(
    String name, {
    Map<String, String>? attributes,
  });

  /// Ties the reports to [installId]; called once the database holds one.
  Future<void> identify(String installId);
}

/// A trace that does nothing.
class NoopTrace implements TelemetryTrace {
  /// Creates the trace.
  const NoopTrace();

  @override
  void setAttribute(String name, String value) {}

  @override
  void setMetric(String name, int value) {}

  @override
  Future<void> stop() async {}
}

/// The implementation used by tests, the desktop and a build without
/// Firebase.
class NoopTelemetry implements Telemetry {
  /// Creates the no-op reporter.
  const NoopTelemetry({this.installId});

  @override
  final String? installId;

  @override
  bool get enabled => false;

  @override
  void log(String message) {}

  @override
  void setKey(String name, Object value) {}

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
    Map<String, Object>? keys,
  }) async {}

  @override
  Future<void> event(String name, {Map<String, Object>? parameters}) async {}

  @override
  TelemetryTrace startTrace(String name, {Map<String, String>? attributes}) =>
      const NoopTrace();

  @override
  Future<void> identify(String installId) async {}
}

/// The reporter the app uses; `main` overrides it with the Firebase one.
final telemetryProvider = Provider<Telemetry>((ref) => const NoopTelemetry());
