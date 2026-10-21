import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/editor/data/sample_models.dart';
import 'package:cutter/features/editor/data/sample_project.dart';
import 'package:cutter/features/editor/presentation/media_picker_page.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Lets the user choose a template, fill its media slots and create a project.
///
/// Pops with the new [SampleProject] once every slot has supported media.
class TemplatesPage extends StatefulWidget {
  /// Creates the templates page.
  const TemplatesPage({super.key});

  @override
  State<TemplatesPage> createState() => _TemplatesPageState();
}

class _TemplatesPageState extends State<TemplatesPage> {
  SampleTemplate? _template;
  final Map<String, SampleAsset> _filled = <String, SampleAsset>{};

  int get _missingSlots {
    final template = _template;
    if (template == null) return 0;
    return template.slots.length - _filled.length;
  }

  bool get _canCreate => _template != null && _missingSlots == 0;

  void _selectTemplate(SampleTemplate template) {
    setState(() {
      _template = template;
      _filled.clear();
    });
  }

  Future<void> _pickMedia(SampleSlot slot) async {
    final asset = await Navigator.of(context).push<SampleAsset>(
      MaterialPageRoute<SampleAsset>(
        builder: (BuildContext context) =>
            MediaPickerPage(kindFilter: slot.kind),
      ),
    );
    if (asset == null || !mounted) return;
    if (!asset.supported) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.templateSlotUnsupported(asset.name))),
      );
      return;
    }
    setState(() => _filled[slot.id] = asset);
  }

  void _create() {
    final template = _template;
    if (template == null || !_canCreate) return;
    final l10n = AppLocalizations.of(context);
    Navigator.of(context).pop(_projectFrom(template, l10n));
  }

  SampleProject _projectFrom(SampleTemplate template, AppLocalizations l10n) {
    final layers = <SampleLayer>[
      for (final slot in template.slots)
        SampleLayer(
          id: 'layer-${slot.id}',
          kind: slot.kind,
          name: _kindLabel(l10n, slot.kind),
          clips: <SampleClip>[_clipFor(slot, _filled[slot.id]!)],
        ),
    ];
    return SampleProject(
      id: 'project-${template.id}',
      name: template.name,
      layers: layers,
    );
  }

  SampleClip _clipFor(SampleSlot slot, SampleAsset asset) {
    return SampleClip(
      id: 'clip-${slot.id}',
      name: asset.name,
      kind: slot.kind,
      startMs: 0,
      durationMs: asset.durationMs,
      inMs: 0,
      outMs: asset.durationMs,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.templatesTitle)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final margin = marginFor(windowClassOf(constraints.maxWidth));
            return Column(
              children: <Widget>[
                Expanded(child: _body(context, margin)),
                _Footer(
                  margin: margin,
                  missingSlots: _missingSlots,
                  hasTemplate: _template != null,
                  onCreate: _canCreate ? _create : null,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _body(BuildContext context, double margin) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final template = _template;
    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: margin,
        vertical: AppSpacing.sm,
      ),
      children: <Widget>[
        for (final entry in sampleTemplates)
          _TemplateTile(
            template: entry,
            selected: entry.id == template?.id,
            onTap: () => _selectTemplate(entry),
          ),
        if (template != null) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          Text(l10n.templateSlotsHeading, style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          for (final slot in template.slots)
            _SlotRow(
              slot: slot,
              asset: _filled[slot.id],
              onPick: () => _pickMedia(slot),
            ),
        ],
      ],
    );
  }
}

/// One template choice; a check icon and selected state mark the choice.
class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final SampleTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: template.name,
      excludeSemantics: true,
      child: ListTile(
        minTileHeight: AppSizes.minTarget,
        selected: selected,
        selectedTileColor: scheme.primaryContainer,
        selectedColor: scheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
        ),
        leading: const Icon(Icons.dashboard_customize_outlined),
        title: Text(template.name),
        trailing: selected ? const Icon(Icons.check) : null,
        onTap: onTap,
      ),
    );
  }
}

/// One media slot: its kind, the chosen file name and a button to pick media.
class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.slot,
    required this.asset,
    required this.onPick,
  });

  final SampleSlot slot;
  final SampleAsset? asset;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final kindLabel = _kindLabel(l10n, slot.kind);
    final chosen = asset;
    final actionLabel =
        chosen == null ? l10n.templateSlotChoose : l10n.templateSlotReplace;
    return ListTile(
      minTileHeight: AppSizes.minTarget,
      leading: Icon(
        chosen == null ? _kindIcon(slot.kind) : Icons.check_circle_outline,
        color: scheme.onSurfaceVariant,
      ),
      title: Text(kindLabel),
      subtitle: chosen == null ? null : Text(chosen.name),
      trailing: TextButton(
        onPressed: onPick,
        child: Semantics(
          label: '$actionLabel, $kindLabel',
          excludeSemantics: true,
          child: Text(actionLabel),
        ),
      ),
    );
  }
}

/// Status line and the Create project button.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.margin,
    required this.missingSlots,
    required this.hasTemplate,
    required this.onCreate,
  });

  final double margin;
  final int missingSlots;
  final bool hasTemplate;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final showMissing = hasTemplate && missingSlots > 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        margin,
        AppSpacing.sm,
        margin,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (showMissing)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  l10n.templateMissingSlots(missingSlots),
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          FilledButton(
            onPressed: onCreate,
            child: Text(l10n.templateCreateProject),
          ),
        ],
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
