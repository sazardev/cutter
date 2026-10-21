import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/editor/domain/canvas.dart';
import 'package:cutter/features/editor/domain/template.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/home/presentation/template_labels.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double _contentMaxWidth = 720;
const double _optionIconSize = 40;
const double _shapeBoxSize = 56;
const int _stepCount = 4;
const List<int> _frameRates = [24, 30, 60];

/// What the guide collected: everything needed to create the project.
class NewProjectRequest {
  /// Creates a request.
  const NewProjectRequest({
    required this.name,
    required this.canvas,
    this.templateId,
  });

  /// The project name, not empty.
  final String name;

  /// The frame the project renders to.
  final Canvas canvas;

  /// The template whose layers the project starts with, or null for blank.
  final String? templateId;
}

/// The guide behind "New project": start (blank or template), screen shape,
/// frame rate and name. It pops a [NewProjectRequest], or null when closed.
class NewProjectPage extends ConsumerStatefulWidget {
  /// Creates the guide; [suggestedName] fills the name field.
  const NewProjectPage({
    required this.suggestedName,
    this.initialTemplateId,
    super.key,
  });

  /// The name offered in the last step.
  final String suggestedName;

  /// A template picked before opening the guide; the guide then starts at
  /// the format step.
  final String? initialTemplateId;

  @override
  ConsumerState<NewProjectPage> createState() => _NewProjectPageState();
}

class _NewProjectPageState extends ConsumerState<NewProjectPage> {
  late final TextEditingController _name;
  late int _step = widget.initialTemplateId == null ? 0 : 1;
  late String? _templateId = widget.initialTemplateId;
  CanvasPreset _shape = CanvasPreset.portrait;
  int _fps = 30;
  bool _nameMissing = false;

  bool get _isLast => _step == _stepCount - 1;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.suggestedName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _create() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameMissing = true);
      return;
    }
    Navigator.of(context).pop(
      NewProjectRequest(
        name: name,
        templateId: _templateId,
        canvas: _shape.canvas(fps: _fps),
      ),
    );
  }

  void _skip() {
    final name = _name.text.trim();
    Navigator.of(context).pop(
      NewProjectRequest(
        name: name.isEmpty ? widget.suggestedName : name,
        templateId: _templateId,
        canvas: _shape.canvas(fps: _fps),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final margin = marginFor(windowClassOf(MediaQuery.sizeOf(context).width));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.newProjectTitle)),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(value: (_step + 1) / _stepCount),
            Padding(
              padding: EdgeInsets.fromLTRB(margin, AppSpacing.md, margin, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  l10n.newProjectStepLabel(_step + 1, _stepCount),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: motionDuration(
                  context,
                  const Duration(milliseconds: 200),
                ),
                child: Align(
                  key: ValueKey(_step),
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _contentMaxWidth,
                    ),
                    child: ListView(
                      padding: EdgeInsets.all(margin),
                      children: [_stepBody(context)],
                    ),
                  ),
                ),
              ),
            ),
            _Footer(
              margin: margin,
              canGoBack: _step > 0,
              isLast: _isLast,
              onBack: () => setState(() => _step--),
              onNext: () => setState(() => _step++),
              onCreate: _create,
              onSkip: _skip,
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBody(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (_step) {
      case 0:
        return _StepScaffold(
          title: l10n.newProjectStartTitle,
          body: l10n.newProjectStartBody,
          child: _StartStep(
            selectedTemplateId: _templateId,
            onSelect: (id, suggestedShape) => setState(() {
              _templateId = id;
              if (suggestedShape != null) _shape = suggestedShape;
            }),
          ),
        );
      case 1:
        return _StepScaffold(
          title: l10n.newProjectFormatTitle,
          body: l10n.newProjectFormatBody,
          child: _FormatStep(
            selected: _shape,
            onSelect: (shape) => setState(() => _shape = shape),
          ),
        );
      case 2:
        return _StepScaffold(
          title: l10n.newProjectQualityTitle,
          body: l10n.newProjectQualityBody,
          child: _FrameRateStep(
            selected: _fps,
            onSelect: (fps) => setState(() => _fps = fps),
          ),
        );
      default:
        return _StepScaffold(
          title: l10n.newProjectNameTitle,
          body: l10n.newProjectNameBody,
          child: _NameStep(
            controller: _name,
            nameMissing: _nameMissing,
            templateId: _templateId,
            shape: _shape,
            fps: _fps,
            onChanged: () {
              if (_nameMissing) setState(() => _nameMissing = false);
            },
            onSubmitted: _create,
          ),
        );
    }
  }
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    required this.title,
    required this.body,
    required this.child,
  });

  final String title;
  final String body;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: theme.textTheme.headlineSmall),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          body,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        child,
      ],
    );
  }
}

/// A selectable card: leading mark, title, one line, a check when chosen.
class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.leading,
    required this.title,
    required this.selected,
    required this.onTap,
    this.body,
  });

  final Widget leading;
  final String title;
  final String? body;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color:
            selected ? scheme.secondaryContainer : scheme.surfaceContainerHigh,
        shape: theme.cardTheme.shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                leading,
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      if (body != null && body!.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          body!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected ? scheme.primary : scheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: _optionIconSize,
      height: _optionIconSize,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Icon(icon, color: scheme.onPrimaryContainer),
    );
  }
}

class _StartStep extends ConsumerWidget {
  const _StartStep({required this.selectedTemplateId, required this.onSelect});

  final String? selectedTemplateId;
  final void Function(String? templateId, CanvasPreset? shape) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final templates = ref.watch(_templatesProvider).valueOrNull ?? const [];
    return Column(
      children: [
        _OptionCard(
          leading: const _Badge(Icons.crop_free),
          title: l10n.newProjectBlankTitle,
          body: l10n.newProjectBlankBody,
          selected: selectedTemplateId == null,
          onTap: () => onSelect(null, null),
        ),
        for (final template in templates) ...[
          const SizedBox(height: AppSpacing.sm),
          Builder(
            builder: (context) {
              final labels = templateLabels(l10n, template);
              return _OptionCard(
                leading: const _Badge(Icons.dashboard_customize_outlined),
                title: labels.title,
                body: labels.body,
                selected: selectedTemplateId == template.id,
                onTap: () => onSelect(template.id, null),
              );
            },
          ),
        ],
      ],
    );
  }
}

final _templatesProvider = FutureProvider<List<Template>>(
  (ref) => ref.watch(templateCatalogProvider).all(),
);

class _FormatStep extends StatelessWidget {
  const _FormatStep({required this.selected, required this.onSelect});

  final CanvasPreset selected;
  final ValueChanged<CanvasPreset> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        for (final preset in CanvasPreset.values) ...[
          if (preset != CanvasPreset.values.first)
            const SizedBox(height: AppSpacing.sm),
          _OptionCard(
            leading: _ShapePreview(preset),
            title: '${_name(l10n, preset)} · ${_ratio(preset)}',
            body: '${_help(l10n, preset)} · '
                '${l10n.canvasSize(preset.width, preset.height)}',
            selected: selected == preset,
            onTap: () => onSelect(preset),
          ),
        ],
      ],
    );
  }

  String _name(AppLocalizations l10n, CanvasPreset preset) => switch (preset) {
        CanvasPreset.portrait => l10n.canvasPortrait,
        CanvasPreset.landscape => l10n.canvasLandscape,
        CanvasPreset.square => l10n.canvasSquare,
        CanvasPreset.feed => l10n.canvasFeed,
      };

  String _help(AppLocalizations l10n, CanvasPreset preset) => switch (preset) {
        CanvasPreset.portrait => l10n.formatPortraitHelp,
        CanvasPreset.landscape => l10n.formatLandscapeHelp,
        CanvasPreset.square => l10n.formatSquareHelp,
        CanvasPreset.feed => l10n.formatFeedHelp,
      };

  String _ratio(CanvasPreset preset) => switch (preset) {
        CanvasPreset.portrait => '9:16',
        CanvasPreset.landscape => '16:9',
        CanvasPreset.square => '1:1',
        CanvasPreset.feed => '4:5',
      };
}

/// The preset drawn as a filled rectangle with its own proportions.
class _ShapePreview extends StatelessWidget {
  const _ShapePreview(this.preset);

  final CanvasPreset preset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = preset.width / preset.height;
    final width = ratio >= 1 ? _shapeBoxSize : _shapeBoxSize * ratio;
    final height = ratio >= 1 ? _shapeBoxSize / ratio : _shapeBoxSize;
    return SizedBox(
      width: _shapeBoxSize,
      height: _shapeBoxSize,
      child: Center(
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(AppRadii.extraSmall),
          ),
        ),
      ),
    );
  }
}

class _FrameRateStep extends StatelessWidget {
  const _FrameRateStep({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final labels = {
      24: (l10n.fpsCinematicTitle, l10n.fpsCinematicBody, Icons.movie_outlined),
      30: (
        l10n.fpsStandardTitle,
        l10n.fpsStandardBody,
        Icons.slow_motion_video
      ),
      60: (l10n.fpsSmoothTitle, l10n.fpsSmoothBody, Icons.speed),
    };
    return Column(
      children: [
        for (final fps in _frameRates) ...[
          if (fps != _frameRates.first) const SizedBox(height: AppSpacing.sm),
          _OptionCard(
            leading: _Badge(labels[fps]!.$3),
            title: labels[fps]!.$1,
            body: labels[fps]!.$2,
            selected: selected == fps,
            onTap: () => onSelect(fps),
          ),
        ],
      ],
    );
  }
}

class _NameStep extends ConsumerWidget {
  const _NameStep({
    required this.controller,
    required this.nameMissing,
    required this.templateId,
    required this.shape,
    required this.fps,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool nameMissing;
  final String? templateId;
  final CanvasPreset shape;
  final int fps;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final templates = ref.watch(_templatesProvider).valueOrNull ?? const [];
    final template = templates.where((t) => t.id == templateId);
    final start = template.isEmpty
        ? l10n.newProjectBlankTitle
        : templateLabels(l10n, template.first).title;
    final shapeName = switch (shape) {
      CanvasPreset.portrait => l10n.canvasPortrait,
      CanvasPreset.landscape => l10n.canvasLandscape,
      CanvasPreset.square => l10n.canvasSquare,
      CanvasPreset.feed => l10n.canvasFeed,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onChanged: (_) => onChanged(),
          onSubmitted: (_) => onSubmitted(),
          decoration: InputDecoration(
            labelText: l10n.projectNameLabel,
            errorText: nameMissing ? l10n.newProjectNameRequired : null,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              _SummaryRow(l10n.newProjectSummaryStart, start),
              const Divider(height: 1),
              _SummaryRow(l10n.newProjectSummaryFormat, shapeName),
              const Divider(height: 1),
              _SummaryRow(l10n.newProjectSummaryFps, '$fps fps'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.canvasSize(shape.width, shape.height),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(value, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.margin,
    required this.canGoBack,
    required this.isLast,
    required this.onBack,
    required this.onNext,
    required this.onCreate,
    required this.onSkip,
  });

  final double margin;
  final bool canGoBack;
  final bool isLast;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onCreate;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: margin,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                if (canGoBack)
                  TextButton(
                    onPressed: onBack,
                    child: Text(l10n.newProjectBack),
                  ),
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      if (!isLast)
                        TextButton(
                          onPressed: onSkip,
                          child: Text(l10n.newProjectSkip),
                        ),
                      FilledButton(
                        onPressed: isLast ? onCreate : onNext,
                        child: Text(
                          isLast ? l10n.newProjectCreate : l10n.onboardingNext,
                        ),
                      ),
                    ],
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
