import 'dart:async';

import 'package:cutter/core/settings/settings_store.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the timeline sits relative to the preview.
enum TimelinePosition {
  /// Under the preview: the classic phone and editor layout.
  bottom,

  /// Over the preview.
  top,

  /// Beside the preview, on the right; wide windows only (narrow ones fall
  /// back to [bottom]).
  side,
}

/// How the editor is laid out; kept between sessions.
class EditorLayoutPrefs {
  /// Creates the preferences.
  const EditorLayoutPrefs({
    this.timeline = TimelinePosition.bottom,
    this.railExpanded,
    this.previewShare = defaultPreviewShare,
  });

  /// The share of the room the preview gets until the user drags the
  /// divider.
  static const double defaultPreviewShare = 0.58;

  /// Where the timeline sits.
  final TimelinePosition timeline;

  /// How much of the room shared by the preview and the timeline goes to the
  /// preview: 0 shows only the timeline, 1 only the preview.
  final double previewShare;

  /// Whether the side tool bar shows labels; null until the user chooses,
  /// which follows the window (see [railExpandedAt]).
  final bool? railExpanded;

  /// Whether the side tool bar shows labels in a window [width] wide: by
  /// default only where they leave the preview room (desktop, large tablets).
  bool railExpandedAt(double width) => railExpanded ?? width >= 1200;

  /// Returns a copy with the given fields replaced.
  EditorLayoutPrefs copyWith({
    TimelinePosition? timeline,
    bool? railExpanded,
    double? previewShare,
  }) =>
      EditorLayoutPrefs(
        timeline: timeline ?? this.timeline,
        railExpanded: railExpanded ?? this.railExpanded,
        previewShare: previewShare ?? this.previewShare,
      );
}

const _timelineKey = 'editor.timeline_position';
const _railKey = 'editor.rail_expanded';
const _shareKey = 'editor.preview_share';

/// The device preferences store.
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => SettingsStore(ref.watch(appDatabaseProvider)),
);

/// Loads the layout once and saves every change.
class EditorLayoutController extends Notifier<EditorLayoutPrefs> {
  @override
  EditorLayoutPrefs build() {
    unawaited(_load());
    return const EditorLayoutPrefs();
  }

  Future<void> _load() async {
    final store = ref.read(settingsStoreProvider);
    final timeline = await store.read(_timelineKey);
    final rail = await store.read(_railKey);
    final share = double.tryParse(await store.read(_shareKey) ?? '');
    state = EditorLayoutPrefs(
      timeline: TimelinePosition.values.firstWhere(
        (p) => p.name == timeline,
        orElse: () => TimelinePosition.bottom,
      ),
      railExpanded: rail == null ? null : rail == 'true',
      previewShare:
          (share ?? EditorLayoutPrefs.defaultPreviewShare).clamp(0.0, 1.0),
    );
  }

  /// Puts the timeline at [position].
  Future<void> setTimeline(TimelinePosition position) async {
    state = state.copyWith(timeline: position);
    await ref.read(settingsStoreProvider).write(_timelineKey, position.name);
  }

  /// Gives the preview [share] of the room it shares with the timeline.
  Future<void> setPreviewShare(double share) async {
    final clamped = share.clamp(0.0, 1.0);
    state = state.copyWith(previewShare: clamped);
    await ref
        .read(settingsStoreProvider)
        .write(_shareKey, clamped.toStringAsFixed(3));
  }

  /// Shows or hides the labels of the side tool bar in a window [width]
  /// wide; from then on the choice holds for every window.
  Future<void> toggleRail(double width) async {
    final expanded = !state.railExpandedAt(width);
    state = state.copyWith(railExpanded: expanded);
    await ref.read(settingsStoreProvider).write(_railKey, expanded.toString());
  }
}

/// The editor layout preferences.
final editorLayoutProvider =
    NotifierProvider<EditorLayoutController, EditorLayoutPrefs>(
  EditorLayoutController.new,
);
