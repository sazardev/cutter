import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/editor/presentation/editor_controller.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

const int _msPerSecond = 1000;
const int _secondsPerMinute = 60;
const int _msPerTenth = 100;
const int _tenthsPerSecond = 10;

/// Formats milliseconds as `m:ss.t` (minutes, seconds, tenths).
String formatTransportTime(int ms) {
  final safe = ms < 0 ? 0 : ms;
  final totalSeconds = safe ~/ _msPerSecond;
  final minutes = totalSeconds ~/ _secondsPerMinute;
  final seconds = (totalSeconds % _secondsPerMinute).toString().padLeft(2, '0');
  final tenths = (safe ~/ _msPerTenth) % _tenthsPerSecond;
  return '$minutes:$seconds.$tenths';
}

/// Play or pause button, time label and playhead slider.
class TransportBar extends StatelessWidget {
  /// Creates a transport bar for [controller].
  const TransportBar({required this.controller, super.key});

  /// The editor state this bar shows and drives.
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _TransportContent(controller: controller),
    );
  }
}

class _TransportContent extends StatelessWidget {
  const _TransportContent({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final duration = controller.project.durationMs;
    final playhead = controller.playheadMs.clamp(0, duration);
    final isPlaying = controller.isPlaying;
    final playLabel = isPlaying ? l10n.actionPause : l10n.actionPlay;
    final timeLabel =
        '${formatTransportTime(playhead)} / ${formatTransportTime(duration)}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            FilledButton.icon(
              onPressed: duration == 0 ? null : controller.togglePlay,
              style: FilledButton.styleFrom(
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                minimumSize: const Size(
                  AppSizes.minTarget,
                  AppSizes.minTarget,
                ),
              ),
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              label: Text(playLabel),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  timeLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: playhead.toDouble(),
          max: duration == 0 ? 1 : duration.toDouble(),
          onChanged: duration == 0
              ? null
              : (value) => controller.seek(value.round()),
          semanticFormatterCallback: (value) =>
              formatTransportTime(value.round()),
        ),
      ],
    );
  }
}
