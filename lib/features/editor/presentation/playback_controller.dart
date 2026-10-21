import 'dart:async';

import 'package:cutter/core/engine/media_engine.dart';
import 'package:cutter/features/editor/data/engine_timeline.dart';
import 'package:cutter/features/editor/domain/clip_transform.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/missing_media.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the preview shows: where the playhead is, whether it plays, and the
/// texture the engine draws into.
class PlaybackUi {
  /// Creates the playback state.
  const PlaybackUi({
    this.positionMs = 0,
    this.playing = false,
    this.textureId,
    this.unavailable = false,
    this.updatedAt,
  });

  /// The playhead in milliseconds.
  final int positionMs;

  /// Whether the preview is playing.
  final bool playing;

  /// The texture the engine draws into, null until the preview is open.
  final int? textureId;

  /// True when the engine could not open a preview on this device.
  final bool unavailable;

  /// When [positionMs] was measured, so a moving playhead can be drawn
  /// between engine updates.
  final DateTime? updatedAt;

  /// Returns a copy with the given fields replaced.
  PlaybackUi copyWith({
    int? positionMs,
    bool? playing,
    int? textureId,
    bool? unavailable,
    DateTime? updatedAt,
  }) {
    return PlaybackUi(
      positionMs: positionMs ?? this.positionMs,
      playing: playing ?? this.playing,
      textureId: textureId ?? this.textureId,
      unavailable: unavailable ?? this.unavailable,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Owns the engine preview of the open project: sends every edit to the
/// engine and reports the playhead back.
class PlaybackController extends AutoDisposeNotifier<PlaybackUi> {
  PreviewSession? _session;
  StreamSubscription<PlaybackState>? _states;
  Project? _project;
  final Map<String, Map<String, double>> _adjustmentPreviews = {};
  final Map<String, ClipTransform> _transformPreviews = {};
  String? _isolated;
  bool _disposed = false;
  (int, int)? _bounds;

  @override
  PlaybackUi build() {
    ref
      ..onDispose(() {
        _disposed = true;
        unawaited(_states?.cancel());
        _session?.dispose();
      })
      ..listen(
        editorControllerProvider.select((s) => s.valueOrNull?.project),
        (previous, next) {
          if (next == null || identical(next, _project)) return;
          _project = next;
          _adjustmentPreviews.clear();
          _transformPreviews.clear();
          _push();
        },
        fireImmediately: true,
      );
    unawaited(_open());
    return const PlaybackUi();
  }

  Future<void> _open() async {
    try {
      final session = await ref.read(mediaEngineProvider).openPreview();
      if (_disposed) {
        session.dispose();
        return;
      }
      _session = session;
      _states = session.states.listen(_onState);
      final bounds = _bounds;
      if (bounds != null) session.setBounds(bounds.$1, bounds.$2);
      _push();
      session.seek(state.positionMs);
      state = state.copyWith(textureId: session.textureId);
    } on Object {
      if (!_disposed) state = state.copyWith(unavailable: true);
    }
  }

  void _onState(PlaybackState update) {
    state = state.copyWith(
      positionMs: update.positionMs,
      playing: update.playing,
      updatedAt: DateTime.now(),
    );
  }

  /// The project the engine plays: the whole one, or only the isolated
  /// clip moved to the start.
  Project? get _played {
    final project = _project;
    final id = _isolated;
    if (project == null || id == null) return project;
    final clip = project.clipById(id);
    final layer = project.layerOfClip(id);
    if (clip == null || layer == null) return project;
    return project.withLayers([
      layer.withClips([clip.copyWith(startMs: 0)]),
    ]);
  }

  /// Plays only clip [clipId] from zero, for its own editor; null goes
  /// back to the whole project, with the playhead where it was in the clip.
  void isolate(String? clipId) {
    if (_disposed || clipId == _isolated) return;
    final previous = _isolated;
    final position = state.positionMs;
    _isolated = clipId;
    pause();
    _push();
    if (clipId != null) {
      seek(0);
    } else {
      final clip = previous == null ? null : _project?.clipById(previous);
      seek(clip == null ? 0 : clip.startMs + position);
    }
  }

  /// The clip being edited on its own, if any.
  String? get isolatedClipId => _isolated;

  void _push() {
    final project = _played;
    final session = _session;
    if (project == null || session == null) return;
    session.setTimeline(
      engineTimelineOf(
        project,
        missingSources:
            ref.read(missingSourcesProvider).valueOrNull ?? const {},
        adjustmentOverrides: _adjustmentPreviews,
        transformOverrides: _transformPreviews,
      ),
    );
  }

  /// The length of the open project.
  int get durationMs => _played?.durationMs ?? 0;

  /// Starts playing, from the start when the playhead is at the end.
  void play() {
    if (durationMs == 0) return;
    _session?.play();
    final from = state.positionMs >= durationMs ? 0 : state.positionMs;
    state = state.copyWith(
      playing: true,
      positionMs: from,
      updatedAt: DateTime.now(),
    );
  }

  /// Stops playing where the playhead is.
  void pause() {
    _session?.pause();
    state = state.copyWith(playing: false, updatedAt: DateTime.now());
  }

  /// Plays when paused, pauses when playing.
  void toggle() => state.playing ? pause() : play();

  /// Moves the playhead to [ms], clamped to the project.
  void seek(int ms) {
    final clamped = ms.clamp(0, durationMs);
    _session?.seek(clamped);
    state = state.copyWith(positionMs: clamped, updatedAt: DateTime.now());
  }

  /// Moves the playhead by one frame of the canvas, forwards or backwards.
  void stepFrame({required bool forward}) {
    final frameMs = 1000 ~/ (_project?.canvas.fps ?? 30);
    pause();
    seek(state.positionMs + (forward ? frameMs : -frameMs));
  }

  /// The size, in physical pixels, the preview is shown at.
  void setBounds(int width, int height) {
    if (_bounds == (width, height)) return;
    _bounds = (width, height);
    _session?.setBounds(width, height);
  }

  /// Shows [transform] on clip [clipId] while a gesture moves it; null goes
  /// back to the saved one.
  void previewTransform(String clipId, ClipTransform? transform) {
    if (transform == null) {
      _transformPreviews.remove(clipId);
    } else {
      _transformPreviews[clipId] = transform;
    }
    _push();
  }

  /// Shows [adjustments] on clip [clipId] before they are saved; null goes
  /// back to the saved values.
  void previewAdjustments(String clipId, Map<String, double>? adjustments) {
    if (adjustments == null) {
      _adjustmentPreviews.remove(clipId);
    } else {
      _adjustmentPreviews[clipId] = adjustments;
    }
    _push();
  }
}

/// The preview of the open project.
final playbackControllerProvider =
    AutoDisposeNotifierProvider<PlaybackController, PlaybackUi>(
  PlaybackController.new,
);
