import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Identifiers of the filters offered in the inspector.
const List<String> inspectorFilterIds = ['mono', 'warm', 'cool', 'vintage'];

/// Adjustment keys, in the order their sliders are shown.
const List<String> inspectorAdjustmentKeys = [
  'brightness',
  'contrast',
  'saturation',
];

const double _volumeMin = 0;
const double _volumeMax = 1;
const double _adjustmentMin = -1;
const double _adjustmentMax = 1;
const int _volumeDivisions = 20;
const int _adjustmentDivisions = 40;
const int _percentFactor = 100;
const int _adjustmentDecimals = 2;

/// Controls for the selected clip: split, move, reverse, volume, filters and
/// adjustments. Shows a hint when no clip is selected.
class ClipInspector extends StatelessWidget {
  /// Creates the inspector for [clip] with one callback per control.
  const ClipInspector({
    required this.clip,
    required this.canSplit,
    required this.filtersEnabled,
    required this.onSplit,
    required this.onMoveEarlier,
    required this.onMoveLater,
    required this.onReverseChanged,
    required this.onVolumeChanged,
    required this.onFilterChanged,
    required this.onAdjustmentChanged,
    super.key,
  });

  /// The selected clip, or null when nothing is selected.
  final Clip? clip;

  /// True only when the playhead is strictly inside the selected clip.
  final bool canSplit;

  /// False for audio clips: filters and adjustments do not apply to them.
  final bool filtersEnabled;

  /// Called when the user taps Split.
  final VoidCallback onSplit;

  /// Called when the user moves the clip earlier.
  final VoidCallback onMoveEarlier;

  /// Called when the user moves the clip later.
  final VoidCallback onMoveLater;

  /// Called with the new reverse state.
  final ValueChanged<bool> onReverseChanged;

  /// Called with the new volume (0..1).
  final ValueChanged<double> onVolumeChanged;

  /// Called with the filter id, or null for "None".
  final ValueChanged<String?> onFilterChanged;

  /// Called with the adjustment key and its new value (-1..1).
  final void Function(String key, double value) onAdjustmentChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final selected = clip;
    if (selected == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            l10n.selectClipHint,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.inspectorTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _ActionRow(
          canSplit: canSplit,
          onSplit: onSplit,
          onMoveEarlier: onMoveEarlier,
          onMoveLater: onMoveLater,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.reverseLabel),
          value: selected.reversed,
          onChanged: onReverseChanged,
        ),
        _VolumeSection(volume: selected.volume, onChanged: onVolumeChanged),
        const SizedBox(height: AppSpacing.sm),
        _FilterSection(
          selectedId: selected.filterId,
          enabled: filtersEnabled,
          onChanged: onFilterChanged,
        ),
        const SizedBox(height: AppSpacing.sm),
        _AdjustmentSection(
          values: selected.adjustments,
          enabled: filtersEnabled,
          onChanged: onAdjustmentChanged,
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.canSplit,
    required this.onSplit,
    required this.onMoveEarlier,
    required this.onMoveLater,
  });

  final bool canSplit;
  final VoidCallback onSplit;
  final VoidCallback onMoveEarlier;
  final VoidCallback onMoveLater;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        FilledButton.icon(
          onPressed: canSplit ? onSplit : null,
          icon: const Icon(Icons.content_cut),
          label: Text(l10n.splitAction),
        ),
        OutlinedButton.icon(
          onPressed: onMoveEarlier,
          icon: const Icon(Icons.arrow_back),
          label: Text(l10n.moveEarlierAction),
        ),
        OutlinedButton.icon(
          onPressed: onMoveLater,
          icon: const Icon(Icons.arrow_forward),
          label: Text(l10n.moveLaterAction),
        ),
      ],
    );
  }
}

class _VolumeSection extends StatelessWidget {
  const _VolumeSection({required this.volume, required this.onChanged});

  final double volume;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final percent = (volume * _percentFactor).round();
    final label = l10n.volumeLabel(percent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: volume.clamp(_volumeMin, _volumeMax),
                divisions: _volumeDivisions,
                label: label,
                onChanged: onChanged,
              ),
            ),
            TextButton.icon(
              onPressed: volume == 0 ? null : () => onChanged(0),
              icon: const Icon(Icons.volume_off),
              label: Text(l10n.muteAction),
            ),
          ],
        ),
      ],
    );
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({
    required this.selectedId,
    required this.enabled,
    required this.onChanged,
  });

  final String? selectedId;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  String _name(AppLocalizations l10n, String id) => switch (id) {
        'mono' => l10n.filterMono,
        'warm' => l10n.filterWarm,
        'cool' => l10n.filterCool,
        'vintage' => l10n.filterVintage,
        _ => id,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.filtersLabel,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            ChoiceChip(
              label: Text(l10n.filterNone),
              selected: selectedId == null,
              onSelected: enabled ? (_) => onChanged(null) : null,
            ),
            for (final id in inspectorFilterIds)
              ChoiceChip(
                label: Text(_name(l10n, id)),
                selected: selectedId == id,
                onSelected: enabled ? (_) => onChanged(id) : null,
              ),
          ],
        ),
      ],
    );
  }
}

class _AdjustmentSection extends StatelessWidget {
  const _AdjustmentSection({
    required this.values,
    required this.enabled,
    required this.onChanged,
  });

  final Map<String, double> values;
  final bool enabled;
  final void Function(String key, double value) onChanged;

  String _label(AppLocalizations l10n, String key, String value) =>
      switch (key) {
        'brightness' => l10n.brightnessLabel(value),
        'contrast' => l10n.contrastLabel(value),
        'saturation' => l10n.saturationLabel(value),
        _ => '$key $value',
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.adjustmentsLabel,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        for (final key in inspectorAdjustmentKeys)
          _AdjustmentSlider(
            label: _label(
              l10n,
              key,
              (values[key] ?? 0).toStringAsFixed(_adjustmentDecimals),
            ),
            value: values[key] ?? 0,
            enabled: enabled,
            onChanged: (value) => onChanged(key, value),
          ),
      ],
    );
  }
}

class _AdjustmentSlider extends StatelessWidget {
  const _AdjustmentSlider({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        Slider(
          value: value.clamp(_adjustmentMin, _adjustmentMax),
          min: _adjustmentMin,
          divisions: _adjustmentDivisions,
          label: label,
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }
}
