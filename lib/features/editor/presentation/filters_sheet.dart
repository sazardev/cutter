import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/editor/data/sample_models.dart';
import 'package:cutter/features/editor/data/sample_project.dart';
import 'package:cutter/features/editor/presentation/editor_controller.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Opens the filters sheet for the selected clip.
Future<void> showFiltersSheet(
  BuildContext context,
  EditorController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: _FiltersBody(controller: controller),
    ),
  );
}

/// Listens to the controller and shows the filter choices of the selected clip.
class _FiltersBody extends StatelessWidget {
  const _FiltersBody({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final clip = controller.selectedClip;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.none,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(l10n.filtersTitle, style: textTheme.titleLarge),
              ),
              const SizedBox(height: AppSpacing.md),
              if (clip == null)
                Text(
                  l10n.filtersSelectClip,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                )
              else
                _FilterChoices(controller: controller, clip: clip),
            ],
          ),
        );
      },
    );
  }
}

/// The None chip followed by one chip per sample filter.
class _FilterChoices extends StatelessWidget {
  const _FilterChoices({required this.controller, required this.clip});

  final EditorController controller;
  final SampleClip clip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        ChoiceChip(
          label: Text(l10n.filterNone),
          selected: clip.filterId == null,
          onSelected: (_) => controller.setFilter(clip.id, null),
        ),
        for (final filter in sampleFilters)
          ChoiceChip(
            label: Text(filter.name),
            selected: clip.filterId == filter.id,
            onSelected: (_) => controller.setFilter(clip.id, filter.id),
          ),
      ],
    );
  }
}
