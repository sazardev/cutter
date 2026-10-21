import 'dart:async';

import 'package:cutter/core/settings/settings_store.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/settings/data/drift_share_preferences_repository.dart';
import 'package:cutter/features/settings/domain/share_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The share preferences: what shows after an export and what opens by
/// itself. They load once from the database, with the defaults until then,
/// and each change is saved at once.
final sharePreferencesProvider =
    NotifierProvider<SharePreferencesController, SharePreferences>(
  SharePreferencesController.new,
);

/// Holds the share preferences and persists each change.
class SharePreferencesController extends Notifier<SharePreferences> {
  DriftSharePreferencesRepository get _repository =>
      DriftSharePreferencesRepository(
        SettingsStore(ref.read(appDatabaseProvider)),
      );

  @override
  SharePreferences build() {
    unawaited(_load());
    return const SharePreferences();
  }

  Future<void> _load() async {
    try {
      state = await _repository.load();
    } on Object catch (error) {
      debugPrint('Could not read the share preferences: $error');
    }
  }

  /// Replaces the preferences with [change] applied and saves them.
  Future<void> update(
    SharePreferences Function(SharePreferences current) change,
  ) async {
    final next = change(state);
    if (next == state) return;
    state = next;
    try {
      await _repository.save(next);
    } on Object catch (error) {
      // The choice holds for this session; only persistence is lost.
      debugPrint('Could not save the share preferences: $error');
    }
  }

  /// Shows or hides one platform shortcut.
  Future<void> setPlatform(SharePlatform platform, {required bool shown}) {
    return update(
      (current) => current.copyWith(
        platforms: shown
            ? {...current.platforms, platform}
            : current.platforms.where((p) => p != platform).toSet(),
      ),
    );
  }
}
