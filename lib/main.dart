import 'package:cutter/app/app.dart';
import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the database or stops with a clear message: the editor cannot work
/// without its source of truth.
AppDatabase _openDatabaseOrStop() {
  try {
    return openAppDatabase();
  } on Object catch (error, stackTrace) {
    Error.throwWithStackTrace(
      StateError('Could not open the local database: $error'),
      stackTrace,
    );
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final database = _openDatabaseOrStop();
  runApp(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
      child: const CutterApp(),
    ),
  );
}
