import 'dart:collection';
import 'dart:developer' as developer;

import 'package:cutter/core/telemetry/telemetry.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One edit as it happened: what, how long it took, and how it ended.
class EditLogEntry {
  /// Creates the entry.
  const EditLogEntry({
    required this.at,
    required this.label,
    required this.ms,
    required this.failure,
  });

  /// When the edit finished.
  final DateTime at;

  /// The kind of edit, such as `split` or `transform`.
  final String label;

  /// How long the use case took, saving included.
  final int ms;

  /// Why it was rejected, or null when it was applied.
  final String? failure;

  @override
  String toString() {
    // UTC, like the engine's log lines, so both read on one clock.
    final time = at.toUtc().toIso8601String().substring(11, 23);
    final outcome = failure == null ? 'ok' : 'rejected: $failure';
    return '$time $label ${ms}ms $outcome';
  }
}

/// The latest edits of the session, for the diagnostics panel; each one is
/// also written to the developer log (`flutter logs`, DevTools) and left as a
/// crash-report breadcrumb, so a crash shows the edits that led to it. Only
/// the kind of edit, its time and its outcome: nothing the user typed.
class EditLog extends ChangeNotifier {
  /// Creates the log; edits go to [telemetry] as breadcrumbs.
  EditLog({this.telemetry = const NoopTelemetry()});

  /// Where the breadcrumbs go.
  final Telemetry telemetry;

  static const _capacity = 200;

  final Queue<EditLogEntry> _entries = Queue();

  /// The entries, oldest first.
  List<EditLogEntry> get entries => List.unmodifiable(_entries);

  /// Records the outcome of one edit.
  void record(String label, int ms, EditorResult<Object?> result) {
    final entry = EditLogEntry(
      at: DateTime.now(),
      label: label,
      ms: ms,
      failure: switch (result) {
        Ok() => null,
        Err(:final failure) => failure.toString(),
      },
    );
    _entries.addLast(entry);
    while (_entries.length > _capacity) {
      _entries.removeFirst();
    }
    developer.log(entry.toString(), name: 'cutter.edit');
    telemetry.log('edit $entry');
    notifyListeners();
  }
}

/// The edit log of the running app.
final editLogProvider = ChangeNotifierProvider<EditLog>(
  (ref) => EditLog(telemetry: ref.read(telemetryProvider)),
);
