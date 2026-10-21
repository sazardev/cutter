import 'dart:math' as math;

import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/data/engine_timeline.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/playback_controller.dart';
import 'package:cutter/features/editor/presentation/time_format.dart';
import 'package:cutter/features/editor/presentation/timeline/media_previews.dart';
import 'package:cutter/features/editor/presentation/timeline/timeline_painters.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double _barHeight = 64;
const double _handle = 18;

/// Context shown on each side of the kept part: the clip's own length, at
/// least this much.
const int _minContextMs = 5000;

/// A window of the source around the clip, with its kept part between two
/// handles. A long source does not squeeze a short clip into a sliver: the
/// window is the clip plus its own length (at least 5 s) on each side, and
/// it holds still while a handle is dragged.
/// Dragging a handle shows the frame under it in the preview; letting go
/// trims. The playhead of the clip editor runs inside the kept part.
class TrimBar extends ConsumerStatefulWidget {
  /// Creates the bar for [clip].
  const TrimBar({required this.clip, super.key});

  /// The clip trimmed.
  final Clip clip;

  @override
  ConsumerState<TrimBar> createState() => _TrimBarState();
}

class _TrimBarState extends ConsumerState<TrimBar> {
  int? _in;
  int? _out;
  final GlobalKey _bar = GlobalKey();

  /// Between the grab point and the edge it moves, in source milliseconds,
  /// so the handle does not jump to the finger.
  int _grab = 0;

  /// The source time under a global pointer position.
  int? _msAt(Offset global, int windowFrom, int windowSpan) {
    final box = _bar.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.width <= 0) return null;
    final x = box.globalToLocal(global).dx.clamp(0, box.size.width);
    return windowFrom + (x / box.size.width * windowSpan).round();
  }

  Future<void> _commit() async {
    final clip = widget.clip;
    final inMs = _in ?? clip.inPointMs;
    final outMs = _out ?? clip.outPointMs;
    if (inMs != clip.inPointMs || outMs != clip.outPointMs) {
      await ref
          .read(editorControllerProvider.notifier)
          .trimClip(clip.id, inPointMs: inMs, outPointMs: outMs);
    }
    if (mounted) {
      setState(() {
        _in = null;
        _out = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final clip = widget.clip;
    final source = clip.sourceDurationMs.clamp(1, 1 << 40);
    final inMs = _in ?? clip.inPointMs;
    final outMs = _out ?? clip.outPointMs;
    final playhead =
        ref.watch(playbackControllerProvider.select((p) => p.positionMs));
    final minSpan = clip.sourceSpanOf(minClipDurationMs);
    // The window follows the saved points, so it stays put during a drag.
    final margin = (clip.outPointMs - clip.inPointMs).clamp(
      _minContextMs,
      source,
    );
    final windowFrom = (clip.inPointMs - margin).clamp(0, source);
    final windowTo = (clip.outPointMs + margin).clamp(windowFrom + 1, source);
    final windowSpan = windowTo - windowFrom;
    // The neighbours on the layer bound how far the clip may grow: a trim
    // never runs into another clip.
    final layer = ref
        .watch(editorControllerProvider)
        .valueOrNull
        ?.project
        .layerOfClip(clip.id);
    var room = 1 << 40;
    var roomBefore = 1 << 40;
    for (final other in layer?.clips ?? const <Clip>[]) {
      if (other.id == clip.id) continue;
      if (other.startMs >= clip.range.endMs) {
        room = math.min(room, other.startMs - clip.range.endMs);
      }
      if (other.range.endMs <= clip.startMs) {
        roomBefore = math.min(roomBefore, clip.startMs - other.range.endMs);
      }
    }
    final maxOut = math.min(
      windowTo,
      clip.outPointMs + clip.sourceSpanOf(room.clamp(0, 1 << 40)),
    );
    final minIn = math.max(
      windowFrom,
      math.max(
        0,
        clip.inPointMs - clip.sourceSpanOf(math.min(roomBefore, clip.startMs)),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                l10n.trimRange(
                  formatTimecode(inMs, tenths: true),
                  formatTimecode(outMs, tenths: true),
                ),
                style: theme.textTheme.labelMedium,
              ),
              const Spacer(),
              Text(
                formatTimecode(
                  ((outMs - inMs) / clip.speed).round(),
                  tenths: true,
                ),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            key: _bar,
            height: _barHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final zoom = width / windowSpan;
                final whole = clip.copyWith(
                  startMs: 0,
                  inPointMs: windowFrom,
                  outPointMs: windowTo,
                  speed: 1,
                  reversed: false,
                );
                final x0 = (inMs - windowFrom) * zoom;
                final x1 = (outMs - windowFrom) * zoom;
                final playX =
                    (inMs - windowFrom + clip.sourceSpanOf(playhead)) * zoom;
                void dragTo(Offset global, {required bool start}) {
                  final pointer = _msAt(global, windowFrom, windowSpan);
                  if (pointer == null) return;
                  final edgeMs = pointer - _grab;
                  setState(() {
                    if (start) {
                      _in = edgeMs.clamp(minIn, outMs - minSpan);
                    } else {
                      _out = edgeMs.clamp(inMs + minSpan, maxOut);
                    }
                  });
                  // Show the frame under the handle while dragging.
                  final edge = start ? _in! : _out!;
                  ref
                      .read(playbackControllerProvider.notifier)
                      .seek(((edge - inMs) / clip.speed).round());
                }

                return ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.small),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: clip.kind == MediaKind.audio
                            ? _WholeWaveform(clip: whole, zoom: zoom)
                            : CustomPaint(
                                painter: FilmstripPainter(
                                  store: ref.watch(thumbnailStoreProvider),
                                  clip: whole,
                                  zoom: zoom,
                                  placeholder: scheme.surfaceContainerHighest,
                                ),
                              ),
                      ),
                      // Dim what is cut away.
                      Positioned(
                        left: 0,
                        width: x0,
                        top: 0,
                        bottom: 0,
                        child: ColoredBox(
                          color: scheme.scrim.withValues(alpha: 0.6),
                        ),
                      ),
                      Positioned(
                        left: x1,
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: ColoredBox(
                          color: scheme.scrim.withValues(alpha: 0.6),
                        ),
                      ),
                      Positioned(
                        left: x0,
                        width: (x1 - x0).clamp(0, width),
                        top: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.symmetric(
                                horizontal: BorderSide(
                                  color: scheme.primary,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: playX.clamp(0, width - 2),
                        top: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: Container(width: 2, color: scheme.onSurface),
                        ),
                      ),
                      for (final start in [true, false])
                        Positioned(
                          left: (start ? x0 : x1 - _handle).clamp(
                            0,
                            width - _handle,
                          ),
                          top: 0,
                          bottom: 0,
                          width: _handle,
                          child: Semantics(
                            label: start
                                ? l10n.trimStartHandle
                                : l10n.trimEndHandle,
                            slider: true,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.resizeLeftRight,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onHorizontalDragStart: (d) {
                                  HapticFeedback.selectionClick();
                                  ref
                                      .read(playbackControllerProvider.notifier)
                                      .pause();
                                  final pointer = _msAt(
                                    d.globalPosition,
                                    windowFrom,
                                    windowSpan,
                                  );
                                  _grab = pointer == null
                                      ? 0
                                      : pointer - (start ? inMs : outMs);
                                },
                                onHorizontalDragUpdate: (d) =>
                                    dragTo(d.globalPosition, start: start),
                                onHorizontalDragEnd: (_) => _commit(),
                                child: Container(
                                  color: scheme.primary,
                                  alignment: Alignment.center,
                                  child: Icon(
                                    start
                                        ? Icons.chevron_left
                                        : Icons.chevron_right,
                                    size: 16,
                                    color: scheme.onPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WholeWaveform extends ConsumerWidget {
  const _WholeWaveform({required this.clip, required this.zoom});

  final Clip clip;
  final double zoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final peaks = ref
        .watch(
          waveformProvider(
            (filePathOf(clip.sourceUri), clip.sourceDurationMs),
          ),
        )
        .valueOrNull;
    return ColoredBox(
      color: scheme.secondaryContainer,
      child: CustomPaint(
        painter: WaveformPainter(
          peaks: peaks ?? const [],
          clip: clip,
          zoom: zoom,
          color: scheme.onSecondaryContainer.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}
