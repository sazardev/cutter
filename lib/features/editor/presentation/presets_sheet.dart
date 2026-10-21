import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/editor/data/sample_models.dart';
import 'package:cutter/features/editor/presentation/editor_controller.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Opens the presets sheet: save the selected clip's settings, apply a preset.
Future<void> showPresetsSheet(
  BuildContext context,
  EditorController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _PresetsSheet(controller: controller),
  );
}

/// Name field, save action and the list of presets with an Apply action each.
class _PresetsSheet extends StatefulWidget {
  const _PresetsSheet({required this.controller});

  final EditorController controller;

  @override
  State<_PresetsSheet> createState() => _PresetsSheetState();
}

class _PresetsSheetState extends State<_PresetsSheet> {
  final TextEditingController _nameField = TextEditingController();
  String? _status;

  @override
  void initState() {
    super.initState();
    _nameField.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _nameField.removeListener(_onNameChanged);
    _nameField.dispose();
    super.dispose();
  }

  void _onNameChanged() => setState(() => _status = null);

  void _save(AppLocalizations l10n) {
    final name = _nameField.text.trim();
    if (name.isEmpty) return;
    final outcome = widget.controller.savePreset(name);
    if (outcome != EditorOutcome.ok) {
      setState(() => _status = l10n.presetsSelectClipHint);
      return;
    }
    _nameField.clear();
    setState(() => _status = l10n.presetSavedMessage(name));
  }

  void _apply(AppLocalizations l10n, SamplePreset preset) {
    final outcome = widget.controller.applyPreset(preset.id);
    setState(() {
      _status = outcome == EditorOutcome.ok
          ? l10n.presetAppliedMessage(preset.name)
          : l10n.presetsSelectClipHint;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final insets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.none,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(context, l10n),
              const SizedBox(height: AppSpacing.lg),
              _buildSaveForm(context, l10n),
              if (_status != null) _buildStatus(context, _status!),
              const SizedBox(height: AppSpacing.lg),
              _buildPresetList(context, l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    return Semantics(
      header: true,
      child: Text(
        l10n.presetsTitle,
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
  }

  Widget _buildSaveForm(BuildContext context, AppLocalizations l10n) {
    final hasClip = widget.controller.selectedClip != null;
    final canSave = hasClip && _nameField.text.trim().isNotEmpty;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _nameField,
          enabled: hasClip,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: l10n.presetNameLabel,
            helperText: hasClip ? null : l10n.presetsSelectClipHint,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: canSave ? (_) => _save(l10n) : null,
        ),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: canSave ? () => _save(l10n) : null,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: Text(
              l10n.presetSaveAction,
              style: theme.textTheme.labelLarge,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatus(BuildContext context, String message) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Semantics(
        liveRegion: true,
        child: Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildPresetList(BuildContext context, AppLocalizations l10n) {
    final presets = widget.controller.presets;
    if (presets.isEmpty) return _EmptyPresets(l10n: l10n);
    final hasClip = widget.controller.selectedClip != null;
    return Column(
      children: [
        for (final preset in presets)
          _PresetRow(
            preset: preset,
            applyLabel: l10n.presetApplyAction,
            semanticLabel: l10n.presetApplySemantics(preset.name),
            onApply: hasClip ? () => _apply(l10n, preset) : null,
          ),
      ],
    );
  }
}

/// Empty state: a short title and one sentence; the save form above is the
/// action.
class _EmptyPresets extends StatelessWidget {
  const _EmptyPresets({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Column(
          children: [
            Icon(
              Icons.bookmarks_outlined,
              size: AppSpacing.giant,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.presetsEmptyTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.presetsEmptyBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// One saved preset with its Apply button.
class _PresetRow extends StatelessWidget {
  const _PresetRow({
    required this.preset,
    required this.applyLabel,
    required this.semanticLabel,
    required this.onApply,
  });

  final SamplePreset preset;
  final String applyLabel;
  final String semanticLabel;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSizes.minTarget),
      child: Row(
        children: [
          Expanded(
            child: Text(preset.name, style: theme.textTheme.bodyLarge),
          ),
          Semantics(
            label: semanticLabel,
            button: true,
            excludeSemantics: true,
            enabled: onApply != null,
            onTap: onApply,
            child: TextButton(
              onPressed: onApply,
              child: Text(applyLabel),
            ),
          ),
        ],
      ),
    );
  }
}
