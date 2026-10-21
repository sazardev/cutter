import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/editor/data/sample_models.dart';
import 'package:cutter/features/editor/presentation/editor_controller.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

const int _msPerSecond = 1000;
const int _secondsPerMinute = 60;
const int _tenthMs = 100;
const int _percentScale = 100;
const double _adjustmentMin = -1;
const double _adjustmentMax = 1;
const String _brightnessKey = 'brightness';
const String _contrastKey = 'contrast';
const String _saturationKey = 'saturation';

/// Opens the inspector for the selected clip: trim range, volume and
/// adjustments.
Future<void> showClipInspector(
  BuildContext context,
  EditorController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => _InspectorBody(controller: controller),
  );
}

String _formatMs(int ms) {
  final minutes = ms ~/ (_msPerSecond * _secondsPerMinute);
  final seconds = (ms ~/ _msPerSecond) % _secondsPerMinute;
  final tenths = (ms % _msPerSecond) ~/ _tenthMs;
  return '$minutes:${seconds.toString().padLeft(2, '0')}.$tenths';
}

/// Listens to the controller and shows the controls of the selected clip.
class _InspectorBody extends StatelessWidget {
  const _InspectorBody({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final margin = marginFor(windowClassOf(MediaQuery.sizeOf(context).width));
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final clip = controller.selectedClip;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            margin,
            AppSpacing.none,
            margin,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.inspectorTitle,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (clip == null)
                Text(
                  l10n.inspectorNoClip,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                _ClipControls(
                  key: ValueKey(clip.id),
                  controller: controller,
                  clip: clip,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Controls for one clip; keeps the trim draft while a handle is dragged.
class _ClipControls extends StatefulWidget {
  const _ClipControls({
    required this.controller,
    required this.clip,
    super.key,
  });

  final EditorController controller;
  final SampleClip clip;

  @override
  State<_ClipControls> createState() => _ClipControlsState();
}

class _ClipControlsState extends State<_ClipControls> {
  late final int _maxMs = widget.clip.outMs;
  RangeValues? _draft;
  bool _trimRejected = false;

  RangeValues get _range =>
      _draft ??
      RangeValues(widget.clip.inMs.toDouble(), widget.clip.outMs.toDouble());

  void _commitTrim(RangeValues values) {
    final outcome = widget.controller.trim(
      widget.clip.id,
      values.start.round(),
      values.end.round(),
    );
    setState(() {
      _draft = null;
      _trimRejected = outcome != EditorOutcome.ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final clip = widget.clip;
    final range = _range;
    final volumePercent = (clip.volume * _percentScale).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(clip.name, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel(
          title: l10n.inspectorTrim,
          value: l10n.inspectorTrimValue(
            _formatMs(range.start.round()),
            _formatMs(range.end.round()),
          ),
        ),
        Semantics(
          label: l10n.inspectorTrim,
          child: RangeSlider(
            values: RangeValues(
              range.start.clamp(0, _maxMs.toDouble()),
              range.end.clamp(0, _maxMs.toDouble()),
            ),
            max: _maxMs.toDouble(),
            onChanged: (values) => setState(() {
              _draft = values;
              _trimRejected = false;
            }),
            onChangeEnd: _commitTrim,
          ),
        ),
        if (_trimRejected)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: AppSpacing.lg,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      l10n.inspectorTrimRejected,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        _SectionLabel(
          title: l10n.inspectorVolume,
          value: l10n.inspectorPercent(volumePercent),
        ),
        Semantics(
          label: l10n.inspectorVolume,
          child: Slider(
            value: clip.volume.clamp(0.0, 1.0),
            onChanged: (value) =>
                widget.controller.setClipVolume(clip.id, value),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _adjustment(l10n.adjustBrightness, _brightnessKey),
        _adjustment(l10n.adjustContrast, _contrastKey),
        _adjustment(l10n.adjustSaturation, _saturationKey),
      ],
    );
  }

  Widget _adjustment(String label, String key) {
    final l10n = AppLocalizations.of(context);
    final value = (widget.clip.adjustments[key] ?? 0)
        .clamp(_adjustmentMin, _adjustmentMax);
    final percent = (value * _percentScale).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(title: label, value: l10n.inspectorPercent(percent)),
        Semantics(
          label: label,
          child: Slider(
            value: value,
            min: _adjustmentMin,
            onChanged: (next) =>
                widget.controller.setAdjustment(widget.clip.id, key, next),
          ),
        ),
      ],
    );
  }
}

/// A control title on the left and its current value on the right.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: theme.textTheme.labelLarge),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
