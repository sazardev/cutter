import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/editor/data/sample_models.dart';
import 'package:cutter/features/editor/data/sample_project.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

const double _previewAspectRatio = 16 / 9;
const double _maxTintOpacity = 0.4;

/// The preview area: the clips under the playhead stacked in layer order,
/// with the filter label, a reverse indicator and an adjustment tint.
class PreviewCanvas extends StatelessWidget {
  /// Creates the preview canvas.
  const PreviewCanvas({
    required this.project,
    required this.playheadMs,
    super.key,
  });

  /// The project whose clips are previewed.
  final SampleProject project;

  /// Playhead position in milliseconds.
  final int playheadMs;

  /// Visible clips under the playhead, topmost layer first.
  List<SampleClip> _activeClips() {
    final active = <SampleClip>[];
    for (final layer in project.layers) {
      if (layer.kind == LayerKind.audio) continue;
      for (final clip in layer.clips) {
        if (playheadMs >= clip.startMs && playheadMs < clip.endMs) {
          active.add(clip);
        }
      }
    }
    return active;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _activeClips();
    final semanticLabel = active.map((clip) => clip.name).join(', ');

    return AspectRatio(
      aspectRatio: _previewAspectRatio,
      child: Semantics(
        container: true,
        label: semanticLabel,
        child: ExcludeSemantics(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadii.extraLarge),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.extraLarge),
              child: active.isEmpty
                  ? Center(
                      child: Icon(
                        Icons.movie_outlined,
                        size: AppSizes.minTarget,
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  : _ClipStack(clips: active),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the active clips as layered cards, bottom layer first.
class _ClipStack extends StatelessWidget {
  const _ClipStack({required this.clips});

  final List<SampleClip> clips;

  @override
  Widget build(BuildContext context) {
    final bottomFirst = clips.reversed.toList();
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var depth = 0; depth < bottomFirst.length; depth++)
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(depth * AppSpacing.sm),
              child: _ClipCard(clip: bottomFirst[depth]),
            ),
          ),
      ],
    );
  }
}

class _ClipCard extends StatelessWidget {
  const _ClipCard({required this.clip});

  final SampleClip clip;

  Color _background(ColorScheme scheme) {
    return clip.kind == LayerKind.image
        ? scheme.tertiaryContainer
        : scheme.primaryContainer;
  }

  Color _foreground(ColorScheme scheme) {
    return clip.kind == LayerKind.image
        ? scheme.onTertiaryContainer
        : scheme.onPrimaryContainer;
  }

  double _tintOpacity() {
    if (clip.adjustments.isEmpty) return 0;
    final total = clip.adjustments.values
        .fold<double>(0, (sum, value) => sum + value.abs());
    final average = total / clip.adjustments.length;
    return average.clamp(0.0, _maxTintOpacity);
  }

  String? _filterName() {
    final id = clip.filterId;
    if (id == null) return null;
    for (final filter in sampleFilters) {
      if (filter.id == id) return filter.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = _foreground(scheme);
    final filterName = _filterName();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _background(scheme),
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.large),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: scheme.tertiary.withValues(alpha: _tintOpacity()),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    clip.kind == LayerKind.image
                        ? Icons.image_outlined
                        : Icons.videocam_outlined,
                    color: foreground,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      clip.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: foreground),
                    ),
                  ),
                  if (clip.reversed) ...[
                    const SizedBox(width: AppSpacing.sm),
                    _Badge(
                      icon: Icons.fast_rewind,
                      label: AppLocalizations.of(context).actionReverse,
                    ),
                  ],
                  if (filterName != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    _Badge(icon: Icons.auto_awesome, label: filterName),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppSpacing.lg, color: scheme.onSecondaryContainer),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: scheme.onSecondaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}
