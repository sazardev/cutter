import 'dart:math' as math;

import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/domain/clip.dart' as domain;
import 'package:cutter/features/editor/domain/layer.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

const double _pxPerMs = 0.1;
const double _tapTarget = 48;
const double _trackHeight = 48;
const double _rulerHeight = 48;
const double _labelHeight = 24;
const double _playheadWidth = 2;
const double _iconSize = 16;
const int _tickEveryMs = 1000;
const int _minTimelineMs = 30000;
const int _tailPaddingMs = 5000;
const int _msPerSecond = 1000;
const int _secondsPerMinute = 60;

/// Formats a time in milliseconds as `mm:ss.mmm`.
String formatTimelineTime(int ms) {
  final clamped = math.max(0, ms);
  final minutes = clamped ~/ (_msPerSecond * _secondsPerMinute);
  final seconds = (clamped ~/ _msPerSecond) % _secondsPerMinute;
  final millis = clamped % _msPerSecond;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}.'
      '${millis.toString().padLeft(3, '0')}';
}

/// Layer rows with clip blocks, a tappable ruler and the playhead line.
class TimelineView extends StatelessWidget {
  /// Creates the timeline for [project].
  const TimelineView({
    required this.project,
    required this.playheadMs,
    required this.selectedClipId,
    required this.onSeek,
    required this.onSelectClip,
    super.key,
  });

  /// The project whose layers and clips are drawn.
  final Project project;

  /// The playhead position in milliseconds.
  final int playheadMs;

  /// The id of the selected clip, or null when none is selected.
  final String? selectedClipId;

  /// Called with the tapped time in milliseconds when the ruler is tapped.
  final ValueChanged<int> onSeek;

  /// Called with the clip id when a clip block is tapped.
  final ValueChanged<String> onSelectClip;

  int get _timelineMs {
    var latestEnd = 0;
    for (final layer in project.layers) {
      for (final clip in layer.clips) {
        latestEnd = math.max(latestEnd, clip.startMs + clip.durationMs);
      }
    }
    return math.max(
      _minTimelineMs,
      math.max(latestEnd, playheadMs) + _tailPaddingMs,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final width = _timelineMs * _pxPerMs;
    return Semantics(
      container: true,
      label: l10n.timelineLabel,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: SingleChildScrollView(
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Ruler(width: width, onSeek: onSeek),
                    for (var i = 0; i < project.layers.length; i++)
                      _LayerRow(
                        layer: project.layers[i],
                        position: i + 1,
                        selectedClipId: selectedClipId,
                        onSelectClip: onSelectClip,
                      ),
                  ],
                ),
                Positioned(
                  left: playheadMs * _pxPerMs - _playheadWidth / 2,
                  top: 0,
                  bottom: 0,
                  width: _playheadWidth,
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Ruler extends StatelessWidget {
  const _Ruler({required this.width, required this.onSeek});

  final double width;
  final ValueChanged<int> onSeek;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: l10n.rulerLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) =>
            onSeek(math.max(0, (details.localPosition.dx / _pxPerMs).round())),
        child: SizedBox(
          width: width,
          height: _rulerHeight,
          child: CustomPaint(
            painter: _RulerPainter(
              tickColor: scheme.onSurfaceVariant,
              backgroundColor: scheme.surfaceContainer,
            ),
          ),
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({required this.tickColor, required this.backgroundColor});

  final Color tickColor;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);
    final paint = Paint()
      ..color = tickColor
      ..strokeWidth = 1;
    for (var ms = 0; ms * _pxPerMs <= size.width; ms += _tickEveryMs) {
      final x = ms * _pxPerMs;
      final isMinute = ms % (_tickEveryMs * _secondsPerMinute) == 0;
      final tickHeight = isMinute ? size.height / 2 : size.height / 4;
      canvas.drawLine(
        Offset(x, size.height - tickHeight),
        Offset(x, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RulerPainter oldDelegate) =>
      oldDelegate.tickColor != tickColor ||
      oldDelegate.backgroundColor != backgroundColor;
}

class _LayerRow extends StatelessWidget {
  const _LayerRow({
    required this.layer,
    required this.position,
    required this.selectedClipId,
    required this.onSelectClip,
  });

  final Layer layer;
  final int position;
  final String? selectedClipId;
  final ValueChanged<String> onSelectClip;

  String _label(AppLocalizations l10n) {
    // The last dotted segment is the kind's plain name ("video", "image",
    // "audio") whether the domain stores it as an enum or as text.
    final kindName = layer.kind.toString().split('.').last;
    final kind = switch (kindName) {
      'video' => l10n.layerKindVideo,
      'image' => l10n.layerKindImage,
      _ => l10n.layerKindAudio,
    };
    return l10n.layerLabel(position, kind);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final label = _label(l10n);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _labelHeight,
          child: Padding(
            padding: const EdgeInsets.only(left: AppSpacing.sm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: _trackHeight,
          child: Stack(
            children: [
              for (final clip in layer.clips)
                Positioned(
                  left: clip.startMs * _pxPerMs,
                  top: 0,
                  width: math.max(_tapTarget, clip.durationMs * _pxPerMs),
                  height: _trackHeight,
                  child: _ClipBlock(
                    clip: clip,
                    layerLabel: label,
                    selected: clip.id == selectedClipId,
                    onTap: () => onSelectClip(clip.id),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

class _ClipBlock extends StatelessWidget {
  const _ClipBlock({
    required this.clip,
    required this.layerLabel,
    required this.selected,
    required this.onTap,
  });

  final domain.Clip clip;
  final String layerLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final background =
        selected ? scheme.primaryContainer : scheme.secondaryContainer;
    final foreground =
        selected ? scheme.onPrimaryContainer : scheme.onSecondaryContainer;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.small),
      side: BorderSide(
        color: selected ? scheme.primary : scheme.outlineVariant,
        width: selected ? 2 : 1,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: l10n.clipSemanticsLabel(
        layerLabel,
        formatTimelineTime(clip.startMs),
        formatTimelineTime(clip.durationMs),
      ),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 1),
        child: Material(
          color: background,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ClipRect(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Row(
                  children: [
                    if (clip.reversed)
                      Icon(
                        Icons.fast_rewind,
                        size: _iconSize,
                        color: foreground,
                        semanticLabel: l10n.clipReversedIcon,
                      ),
                    if (clip.volume <= 0)
                      Icon(
                        Icons.volume_off,
                        size: _iconSize,
                        color: foreground,
                        semanticLabel: l10n.clipMutedIcon,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
