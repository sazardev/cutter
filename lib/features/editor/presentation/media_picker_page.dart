import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/editor/data/sample_models.dart';
import 'package:cutter/features/editor/data/sample_project.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Lists the sample media and pops with the chosen [SampleAsset].
///
/// Unsupported items stay selectable so the editor can explain the failure.
class MediaPickerPage extends StatelessWidget {
  /// Creates the media picker.
  const MediaPickerPage({super.key, this.kindFilter});

  /// When set, only assets of this kind are listed.
  final LayerKind? kindFilter;

  List<SampleAsset> get _assets {
    final filter = kindFilter;
    if (filter == null) return sampleMediaAssets;
    return sampleMediaAssets
        .where((SampleAsset asset) => asset.kind == filter)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final assets = _assets;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.mediaPickerTitle)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final margin = marginFor(windowClassOf(constraints.maxWidth));
            return ListView.separated(
              padding: EdgeInsets.symmetric(
                horizontal: margin,
                vertical: AppSpacing.sm,
              ),
              itemCount: assets.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const Divider(height: AppSpacing.none),
              itemBuilder: (BuildContext context, int index) =>
                  _AssetTile(asset: assets[index]),
            );
          },
        ),
      ),
    );
  }
}

/// One selectable media item: type icon, name, type label and duration.
class _AssetTile extends StatelessWidget {
  const _AssetTile({required this.asset});

  final SampleAsset asset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final kindLabel = _kindLabel(l10n, asset.kind);
    final duration = _formatDuration(asset.durationMs);
    return Semantics(
      button: true,
      label: '${asset.name}, $kindLabel, $duration',
      excludeSemantics: true,
      child: ListTile(
        minTileHeight: AppSizes.minTarget,
        leading: Icon(_kindIcon(asset.kind), color: scheme.onSurfaceVariant),
        title: Text(asset.name),
        subtitle: Text(kindLabel),
        trailing: Text(
          duration,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        onTap: () => Navigator.of(context).pop(asset),
      ),
    );
  }
}

String _kindLabel(AppLocalizations l10n, LayerKind kind) {
  switch (kind) {
    case LayerKind.video:
      return l10n.layerVideo;
    case LayerKind.image:
      return l10n.layerImage;
    case LayerKind.audio:
      return l10n.layerAudio;
  }
}

IconData _kindIcon(LayerKind kind) {
  switch (kind) {
    case LayerKind.video:
      return Icons.videocam_outlined;
    case LayerKind.image:
      return Icons.image_outlined;
    case LayerKind.audio:
      return Icons.audiotrack_outlined;
  }
}

const int _millisecondsPerSecond = 1000;
const int _secondsPerMinute = 60;
const int _secondDigits = 2;

String _formatDuration(int durationMs) {
  final totalSeconds = durationMs ~/ _millisecondsPerSecond;
  final minutes = totalSeconds ~/ _secondsPerMinute;
  final seconds = (totalSeconds % _secondsPerMinute)
      .toString()
      .padLeft(_secondDigits, '0');
  return '$minutes:$seconds';
}
