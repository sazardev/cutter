import 'dart:async';

import 'package:cutter/core/telemetry/error_throttle.dart';
import 'package:cutter/core/telemetry/telemetry.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

/// Where this build was distributed: `beta` for a release, `dev` otherwise,
/// or whatever `--dart-define=CHANNEL=...` says. Reports of a developer's
/// phone and of a tester's then filter apart in the console.
const String telemetryChannel = String.fromEnvironment(
  'CHANNEL',
  defaultValue: kReleaseMode ? 'beta' : 'dev',
);

/// Starts Crashlytics, Analytics and Performance.
///
/// Returns [NoopTelemetry] when Firebase is not configured (desktop) or the
/// platform channel fails: reporting must never keep the editor closed.
Future<Telemetry> startTelemetry({required bool enabled}) async {
  if (!enabled) return const NoopTelemetry();
  try {
    await Firebase.initializeApp();
    final crashlytics = FirebaseCrashlytics.instance;
    await crashlytics.setCrashlyticsCollectionEnabled(true);
    await crashlytics.setCustomKey(
      'build_mode',
      kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
    );
    await crashlytics.setCustomKey('channel', telemetryChannel);
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
    await FirebasePerformance.instance.setPerformanceCollectionEnabled(true);
    return FirebaseTelemetry._();
  } on Object catch (error, stack) {
    debugPrint('Telemetry: Firebase did not start: $error\n$stack');
    return const NoopTelemetry();
  }
}

/// Crashlytics, Analytics and Performance behind [Telemetry].
class FirebaseTelemetry implements Telemetry {
  FirebaseTelemetry._();

  final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  final ErrorThrottle _throttle = ErrorThrottle();

  @override
  String? installId;

  @override
  bool get enabled => true;

  @override
  void log(String message) {
    unawaited(_crashlytics.log(_clip(message, 1000)));
  }

  @override
  void setKey(String name, Object value) {
    unawaited(
      _crashlytics.setCustomKey(_key(name), _clip(value.toString(), 1000)),
    );
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
    Map<String, Object>? keys,
  }) async {
    // A fatal error always goes; a repeat of a non-fatal one waits its turn.
    if (!fatal && !_throttle.allow(error, stack)) return;
    if (_throttle.suppressed > 0) {
      log('${_throttle.suppressed} repeated errors were not sent');
      _throttle.suppressed = 0;
    }
    for (final entry in (keys ?? const <String, Object>{}).entries) {
      await _crashlytics.setCustomKey(
        _key(entry.key),
        _clip(entry.value.toString(), 1000),
      );
    }
    await _crashlytics.recordError(
      error,
      stack,
      reason: reason == null ? null : _clip(reason, 1000),
      fatal: fatal,
      printDetails: false,
    );
  }

  @override
  Future<void> event(String name, {Map<String, Object>? parameters}) {
    final safe = <String, Object>{};
    var count = 0;
    for (final entry in (parameters ?? const <String, Object>{}).entries) {
      if (count++ == 25) break;
      final value = entry.value;
      safe[_key(entry.key)] = value is String ? _clip(value, 100) : value;
    }
    return _analytics.logEvent(name: _key(name), parameters: safe);
  }

  @override
  TelemetryTrace startTrace(
    String name, {
    Map<String, String>? attributes,
  }) {
    final trace = FirebasePerformance.instance.newTrace(name);
    unawaited(trace.start());
    for (final entry in (attributes ?? const <String, String>{}).entries) {
      trace.putAttribute(_key(entry.key), _clip(entry.value, 100));
    }
    return _FirebaseTrace(trace);
  }

  @override
  Future<void> identify(String installId) async {
    this.installId = installId;
    await _crashlytics.setUserIdentifier(installId);
    await _crashlytics.setCustomKey('install_id', installId);
    await _analytics.setUserId(id: installId);
  }
}

class _FirebaseTrace implements TelemetryTrace {
  _FirebaseTrace(this._trace);

  final Trace _trace;

  @override
  void setAttribute(String name, String value) =>
      _trace.putAttribute(_key(name), _clip(value, 100));

  @override
  void setMetric(String name, int value) => _trace.setMetric(_key(name), value);

  @override
  Future<void> stop() => _trace.stop();
}

/// Analytics and Crashlytics key rules: lowercase letters, digits and
/// underscores, at most 40 characters.
String _key(String value) {
  final cleaned = value
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9_]'), '_')
      .replaceAll(RegExp('^_+'), '');
  final safe = cleaned.isEmpty ? 'value' : cleaned;
  return safe.length <= 40 ? safe : safe.substring(0, 40);
}

String _clip(String value, int max) =>
    value.length <= max ? value : value.substring(0, max);
