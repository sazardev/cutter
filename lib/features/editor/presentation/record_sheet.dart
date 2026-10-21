import 'dart:async';

import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/editor/data/sample_models.dart';
import 'package:cutter/features/editor/data/sample_project.dart';
import 'package:cutter/features/editor/presentation/editor_controller.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// How often the elapsed time label refreshes while recording.
const Duration _elapsedRefresh = Duration(milliseconds: 100);

/// Opens the record sheet: microphone voice-over or camera video.
Future<void> showRecordSheet(
  BuildContext context,
  EditorController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => _RecordSheet(controller: controller),
  );
}

class _RecordSheet extends StatefulWidget {
  const _RecordSheet({required this.controller});

  final EditorController controller;

  @override
  State<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<_RecordSheet> {
  LayerKind _kind = LayerKind.audio;
  bool _recording = false;
  bool _tooShort = false;
  int _startMs = 0;
  int _elapsedMs = 0;
  bool _startedPlayback = false;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;

  bool get _permitted => _kind == LayerKind.audio
      ? samplePermissions.microphone
      : samplePermissions.camera;

  @override
  void dispose() {
    _timer?.cancel();
    if (_recording) _stopPlaybackIfStarted();
    super.dispose();
  }

  void _selectKind(LayerKind kind) {
    if (_recording || _kind == kind) return;
    setState(() {
      _kind = kind;
      _tooShort = false;
    });
  }

  void _start() {
    final controller = widget.controller;
    if (!controller.isPlaying) {
      controller.togglePlay();
      _startedPlayback = controller.isPlaying;
    }
    _startMs = controller.playheadMs;
    _stopwatch
      ..reset()
      ..start();
    _timer = Timer.periodic(_elapsedRefresh, (_) {
      setState(() => _elapsedMs = _stopwatch.elapsedMilliseconds);
    });
    setState(() {
      _recording = true;
      _tooShort = false;
      _elapsedMs = 0;
    });
  }

  void _stop() {
    _timer?.cancel();
    _stopwatch.stop();
    final duration = _stopwatch.elapsedMilliseconds;
    _stopPlaybackIfStarted();
    final outcome = widget.controller.addRecordedClip(
      kind: _kind,
      startMs: _startMs,
      durationMs: duration,
    );
    if (outcome == EditorOutcome.ok) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _recording = false;
      _tooShort = true;
      _elapsedMs = duration;
    });
  }

  void _stopPlaybackIfStarted() {
    if (_startedPlayback && widget.controller.isPlaying) {
      widget.controller.togglePlay();
    }
    _startedPlayback = false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.none,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.recordTitle, style: textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              _KindChoice(
                label: l10n.recordMicrophone,
                icon: Icons.mic,
                selected: _kind == LayerKind.audio,
                onSelected: () => _selectKind(LayerKind.audio),
              ),
              _KindChoice(
                label: l10n.recordCamera,
                icon: Icons.videocam,
                selected: _kind == LayerKind.video,
                onSelected: () => _selectKind(LayerKind.video),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          if (_permitted) _buildRecorder(l10n) else _buildDenied(l10n),
        ],
      ),
    );
  }

  Widget _buildRecorder(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: false,
          label: l10n.recordElapsed(_formatElapsed(_elapsedMs)),
          child: ExcludeSemantics(
            child: Text(
              _formatElapsed(_elapsedMs),
              style: textTheme.displayMedium,
            ),
          ),
        ),
        if (_tooShort) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(Icons.error_outline, color: scheme.error),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.recordTooShort,
                  style: textTheme.bodyMedium?.copyWith(color: scheme.error),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          height: AppSizes.minTarget,
          child: _recording
              ? FilledButton.icon(
                  onPressed: _stop,
                  icon: const Icon(Icons.stop),
                  label: Text(l10n.recordStop),
                )
              : FilledButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.fiber_manual_record),
                  label: Text(l10n.recordStart),
                ),
        ),
      ],
    );
  }

  Widget _buildDenied(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.block, color: scheme.error),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.recordPermissionDeniedTitle,
                    style: textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l10n.recordPermissionDeniedBody,
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          height: AppSizes.minTarget,
          child: FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.fiber_manual_record),
            label: Text(l10n.recordStart),
          ),
        ),
      ],
    );
  }
}

/// A mode choice chip with an icon and a 48dp minimum target.
class _KindChoice extends StatelessWidget {
  const _KindChoice({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSizes.minTarget),
      child: ChoiceChip(
        avatar: Icon(icon),
        label: Text(label),
        selected: selected,
        showCheckmark: true,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

const int _msPerSecond = 1000;
const int _secondsPerMinute = 60;
const int _msPerTenth = 100;
const int _tenthsPerSecond = 10;

/// Formats milliseconds as m:ss.t.
String _formatElapsed(int ms) {
  final totalSeconds = ms ~/ _msPerSecond;
  final minutes = totalSeconds ~/ _secondsPerMinute;
  final seconds = (totalSeconds % _secondsPerMinute).toString().padLeft(2, '0');
  final tenths = (ms ~/ _msPerTenth) % _tenthsPerSecond;
  return '$minutes:$seconds.$tenths';
}
