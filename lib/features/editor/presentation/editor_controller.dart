import 'package:cutter/features/editor/data/sample_models.dart';
import 'package:cutter/features/editor/data/sample_project.dart';
import 'package:flutter/foundation.dart';

/// Result of an edit rule. Expected failures are values, never exceptions.
enum EditorOutcome {
  /// The edit was applied.
  ok,

  /// The edit needs a selected clip and none is selected.
  noClipSelected,

  /// The playhead is not strictly inside the selected clip.
  playheadOutsideClip,

  /// The result would be shorter than the minimum clip duration.
  zeroDuration,

  /// The result would overlap another clip on the same layer.
  overlap,

  /// The target layer holds another kind of media.
  wrongLayerKind,

  /// The media file cannot be imported.
  unsupportedMedia,
}

/// Shortest clip the editor accepts, in milliseconds.
const int minClipDurationMs = 100;

/// Holds the editor UI state over the sample project and applies edit rules.
class EditorController extends ChangeNotifier {
  /// Creates a controller that edits [project].
  EditorController(SampleProject project)
      : _project = project,
        _presets = List<SamplePreset>.of(samplePresets);

  SampleProject _project;
  final List<SamplePreset> _presets;
  int _playheadMs = 0;
  bool _isPlaying = false;
  String? _selectedClipId;
  int _nextId = 1;

  /// The project being edited.
  SampleProject get project => _project;

  /// The presets saved by the user.
  List<SamplePreset> get presets => List<SamplePreset>.unmodifiable(_presets);

  /// Playhead position in milliseconds.
  int get playheadMs => _playheadMs;

  /// Whether the timeline is playing.
  bool get isPlaying => _isPlaying;

  /// Id of the selected clip, or null when nothing is selected.
  String? get selectedClipId => _selectedClipId;

  /// The selected clip, or null when nothing is selected.
  SampleClip? get selectedClip {
    final id = _selectedClipId;
    return id == null ? null : _findClip(id);
  }

  /// True when a clip is selected and the playhead is strictly inside it.
  bool get canSplit {
    final clip = selectedClip;
    if (clip == null) return false;
    return _playheadMs > clip.startMs && _playheadMs < clip.endMs;
  }

  /// Selects the clip with [clipId], or clears the selection with null.
  void select(String? clipId) {
    if (_selectedClipId == clipId) return;
    _selectedClipId = clipId;
    notifyListeners();
  }

  /// Starts or pauses playback; at the end it restarts from the beginning.
  void togglePlay() {
    if (_isPlaying) {
      _isPlaying = false;
      notifyListeners();
      return;
    }
    if (_project.durationMs == 0) return;
    if (_playheadMs >= _project.durationMs) _playheadMs = 0;
    _isPlaying = true;
    notifyListeners();
  }

  /// Moves the playhead to [ms], clamped to the project duration.
  void seek(int ms) {
    _playheadMs = ms.clamp(0, _project.durationMs);
    notifyListeners();
  }

  /// Advances the playhead while playing and stops at the end.
  void tick(int deltaMs) {
    if (!_isPlaying) return;
    final end = _project.durationMs;
    final next = _playheadMs + deltaMs;
    if (next >= end) {
      _playheadMs = end;
      _isPlaying = false;
    } else {
      _playheadMs = next;
    }
    notifyListeners();
  }

  /// Splits the selected clip at the playhead into two adjacent clips.
  EditorOutcome split() {
    final clip = selectedClip;
    if (clip == null) return EditorOutcome.noClipSelected;
    if (!canSplit) return EditorOutcome.playheadOutsideClip;
    final firstDuration = _playheadMs - clip.startMs;
    final firstOut = clip.inMs + firstDuration;
    final first = clip.copyWith(durationMs: firstDuration, outMs: firstOut);
    final second = clip.copyWith(
      id: _newId('clip'),
      startMs: _playheadMs,
      durationMs: clip.durationMs - firstDuration,
      inMs: firstOut,
    );
    _replaceLayers((layer) {
      if (!layer.clips.any((c) => c.id == clip.id)) return layer;
      final clips = <SampleClip>[];
      for (final c in layer.clips) {
        clips.add(c.id == clip.id ? first : c);
        if (c.id == clip.id) clips.add(second);
      }
      return layer.copyWith(clips: clips);
    });
    _selectedClipId = second.id;
    notifyListeners();
    return EditorOutcome.ok;
  }

  /// Sets the in and out points of a clip; rejects results that are too
  /// short or that overlap a neighbour, leaving the clip unchanged.
  EditorOutcome trim(String clipId, int inMs, int outMs) {
    final clip = _findClip(clipId);
    if (clip == null) return EditorOutcome.noClipSelected;
    final duration = outMs - inMs;
    if (inMs < 0 || duration < minClipDurationMs) {
      return EditorOutcome.zeroDuration;
    }
    final layer = _layerOfClip(clipId);
    if (layer != null &&
        _overlaps(layer, clip.startMs, clip.startMs + duration, clipId)) {
      return EditorOutcome.overlap;
    }
    _updateClip(
      clipId,
      (c) => c.copyWith(inMs: inMs, outMs: outMs, durationMs: duration),
    );
    _playheadMs = _playheadMs.clamp(0, _project.durationMs);
    notifyListeners();
    return EditorOutcome.ok;
  }

  /// Moves a clip to [startMs] on the layer [layerId]; the layer must hold the
  /// same kind of media and the range must be free.
  EditorOutcome moveClip(String clipId, String layerId, int startMs) {
    final clip = _findClip(clipId);
    if (clip == null) return EditorOutcome.noClipSelected;
    final target = _findLayer(layerId);
    if (target == null || target.kind != clip.kind) {
      return EditorOutcome.wrongLayerKind;
    }
    final start = startMs < 0 ? 0 : startMs;
    if (_overlaps(target, start, start + clip.durationMs, clipId)) {
      return EditorOutcome.overlap;
    }
    final moved = clip.copyWith(startMs: start);
    _replaceLayers((layer) {
      final without = layer.clips.where((c) => c.id != clipId).toList();
      if (layer.id != layerId) return layer.copyWith(clips: without);
      return layer.copyWith(clips: _sortedByStart([...without, moved]));
    });
    _playheadMs = _playheadMs.clamp(0, _project.durationMs);
    notifyListeners();
    return EditorOutcome.ok;
  }

  /// Moves a layer; [newIndex] follows the ReorderableListView convention.
  void reorderLayer(int oldIndex, int newIndex) {
    final layers = List<SampleLayer>.of(_project.layers);
    if (oldIndex < 0 || oldIndex >= layers.length) return;
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (target < 0 || target >= layers.length || target == oldIndex) return;
    layers.insert(target, layers.removeAt(oldIndex));
    _project = _project.copyWith(layers: layers);
    notifyListeners();
  }

  /// Toggles reverse playback on the selected clip.
  EditorOutcome toggleReverse() {
    final clip = selectedClip;
    if (clip == null) return EditorOutcome.noClipSelected;
    _updateClip(clip.id, (c) => c.copyWith(reversed: !c.reversed));
    notifyListeners();
    return EditorOutcome.ok;
  }

  /// Sets the volume of a clip, clamped to 0..1.
  void setClipVolume(String clipId, double volume) {
    final value = volume.clamp(0.0, 1.0);
    _updateClip(clipId, (c) => c.copyWith(volume: value));
    notifyListeners();
  }

  /// Sets the volume of a layer, clamped to 0..1.
  void setLayerVolume(String layerId, double volume) {
    final value = volume.clamp(0.0, 1.0);
    _replaceLayers(
      (l) => l.id == layerId ? l.copyWith(volume: value) : l,
    );
    notifyListeners();
  }

  /// Mutes or unmutes a layer.
  void toggleLayerMute(String layerId) {
    _replaceLayers(
      (l) => l.id == layerId ? l.copyWith(muted: !l.muted) : l,
    );
    notifyListeners();
  }

  /// Stores the adjustment [key] with [value] on a clip.
  void setAdjustment(String clipId, String key, double value) {
    _updateClip(clipId, (c) {
      final adjustments = Map<String, double>.of(c.adjustments);
      adjustments[key] = value;
      return c.copyWith(adjustments: adjustments);
    });
    notifyListeners();
  }

  /// Applies the filter [filterId] to a clip, or removes it with null.
  void setFilter(String clipId, String? filterId) {
    _updateClip(
      clipId,
      (c) => filterId == null
          ? c.copyWith(clearFilter: true)
          : c.copyWith(filterId: filterId),
    );
    notifyListeners();
  }

  /// Appends the asset at the end of the first layer of its kind.
  EditorOutcome addClipFromAsset(SampleAsset asset) {
    if (!asset.supported) return EditorOutcome.unsupportedMedia;
    final layer = _firstLayerOfKind(asset.kind);
    if (layer == null) return EditorOutcome.wrongLayerKind;
    final clip = SampleClip(
      id: _newId('clip'),
      name: asset.name,
      kind: asset.kind,
      startMs: _layerEndMs(layer),
      durationMs: asset.durationMs,
      inMs: 0,
      outMs: asset.durationMs,
    );
    _appendClip(layer.id, clip);
    _selectedClipId = clip.id;
    notifyListeners();
    return EditorOutcome.ok;
  }

  /// Places a recording at [startMs]; if that range is taken it goes to the
  /// end of the layer so no clip is replaced.
  EditorOutcome addRecordedClip({
    required LayerKind kind,
    required int startMs,
    required int durationMs,
  }) {
    if (durationMs < minClipDurationMs) return EditorOutcome.zeroDuration;
    final layer = _firstLayerOfKind(kind);
    if (layer == null) return EditorOutcome.wrongLayerKind;
    final wanted = startMs < 0 ? 0 : startMs;
    final start = _overlaps(layer, wanted, wanted + durationMs, null)
        ? _layerEndMs(layer)
        : wanted;
    final number = _nextId;
    final clip = SampleClip(
      id: _newId('clip'),
      name: kind == LayerKind.audio
          ? 'Recording-$number.m4a'
          : 'Camera-$number.mp4',
      kind: kind,
      startMs: start,
      durationMs: durationMs,
      inMs: 0,
      outMs: durationMs,
    );
    _appendClip(layer.id, clip);
    _selectedClipId = clip.id;
    notifyListeners();
    return EditorOutcome.ok;
  }

  /// Saves the settings of the selected clip as a preset called [name].
  EditorOutcome savePreset(String name) {
    final clip = selectedClip;
    if (clip == null) return EditorOutcome.noClipSelected;
    _presets.add(
      SamplePreset(
        id: _newId('preset'),
        name: name.trim(),
        filterId: clip.filterId,
        adjustments: Map<String, double>.of(clip.adjustments),
        volume: clip.volume,
      ),
    );
    notifyListeners();
    return EditorOutcome.ok;
  }

  /// Applies the preset [presetId] to the selected clip.
  EditorOutcome applyPreset(String presetId) {
    final clip = selectedClip;
    if (clip == null) return EditorOutcome.noClipSelected;
    final index = _presets.indexWhere((p) => p.id == presetId);
    if (index < 0) return EditorOutcome.noClipSelected;
    final preset = _presets[index];
    _updateClip(
      clip.id,
      (c) => preset.filterId == null
          ? c.copyWith(
              clearFilter: true,
              adjustments: Map<String, double>.of(preset.adjustments),
              volume: preset.volume,
            )
          : c.copyWith(
              filterId: preset.filterId,
              adjustments: Map<String, double>.of(preset.adjustments),
              volume: preset.volume,
            ),
    );
    notifyListeners();
    return EditorOutcome.ok;
  }

  /// Replaces the project and resets playhead, playback and selection.
  void loadProject(SampleProject project) {
    _project = project;
    _playheadMs = 0;
    _isPlaying = false;
    _selectedClipId = null;
    notifyListeners();
  }

  String _newId(String prefix) => '$prefix-${_nextId++}';

  SampleClip? _findClip(String clipId) {
    for (final layer in _project.layers) {
      for (final clip in layer.clips) {
        if (clip.id == clipId) return clip;
      }
    }
    return null;
  }

  SampleLayer? _findLayer(String layerId) {
    for (final layer in _project.layers) {
      if (layer.id == layerId) return layer;
    }
    return null;
  }

  SampleLayer? _layerOfClip(String clipId) {
    for (final layer in _project.layers) {
      if (layer.clips.any((c) => c.id == clipId)) return layer;
    }
    return null;
  }

  SampleLayer? _firstLayerOfKind(LayerKind kind) {
    for (final layer in _project.layers) {
      if (layer.kind == kind) return layer;
    }
    return null;
  }

  int _layerEndMs(SampleLayer layer) {
    var end = 0;
    for (final clip in layer.clips) {
      if (clip.endMs > end) end = clip.endMs;
    }
    return end;
  }

  bool _overlaps(
    SampleLayer layer,
    int startMs,
    int endMs,
    String? ignoreId,
  ) {
    for (final clip in layer.clips) {
      if (clip.id == ignoreId) continue;
      if (startMs < clip.endMs && clip.startMs < endMs) return true;
    }
    return false;
  }

  List<SampleClip> _sortedByStart(List<SampleClip> clips) {
    return List<SampleClip>.of(clips)
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
  }

  void _appendClip(String layerId, SampleClip clip) {
    _replaceLayers(
      (l) => l.id == layerId
          ? l.copyWith(clips: _sortedByStart([...l.clips, clip]))
          : l,
    );
  }

  void _updateClip(String clipId, SampleClip Function(SampleClip) change) {
    _replaceLayers(
      (layer) => layer.copyWith(
        clips: [
          for (final clip in layer.clips)
            if (clip.id == clipId) change(clip) else clip,
        ],
      ),
    );
  }

  void _replaceLayers(SampleLayer Function(SampleLayer) change) {
    _project = _project.copyWith(
      layers: [for (final layer in _project.layers) change(layer)],
    );
  }
}
