import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/presentation/layout/editor_layout.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the timeline sits, drawn as small diagrams, and whether the side
/// tool bar shows its labels. Applies at once and is remembered.
class LayoutPanel extends ConsumerWidget {
  /// Creates the panel.
  const LayoutPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final prefs = ref.watch(editorLayoutProvider);
    final controller = ref.read(editorLayoutProvider.notifier);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 600;
    final options = [
      (TimelinePosition.bottom, l10n.layoutBottom),
      (TimelinePosition.top, l10n.layoutTop),
      (TimelinePosition.side, l10n.layoutSide),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final (position, label) in options)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: _LayoutTile(
                    position: position,
                    label: label,
                    selected: prefs.timeline == position,
                    enabled: position != TimelinePosition.side || wide,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      controller.setTimeline(position);
                    },
                  ),
                ),
              ),
          ],
        ),
        if (!wide)
          Text(
            l10n.layoutSideWideOnly,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (wide)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.layoutRailLabels),
            value: prefs.railExpandedAt(width),
            onChanged: (_) => controller.toggleRail(width),
          ),
      ],
    );
  }
}

class _LayoutTile extends StatelessWidget {
  const _LayoutTile({
    required this.position,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final TimelinePosition position;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    Widget block(int flex, {bool timeline = false}) => Expanded(
          flex: flex,
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: timeline ? ink.withValues(alpha: 0.35) : null,
              border: Border.all(color: ink, width: 1.5),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
    final diagram = switch (position) {
      TimelinePosition.bottom => Column(
          children: [block(3), block(2, timeline: true)],
        ),
      TimelinePosition.top => Column(
          children: [block(2, timeline: true), block(3)],
        ),
      TimelinePosition.side => Row(
          children: [block(3), block(2, timeline: true)],
        ),
    };
    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.medium),
          onTap: enabled ? onTap : null,
          child: Ink(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadii.medium),
            ),
            child: Column(
              children: [
                SizedBox(height: 56, width: 64, child: diagram),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(color: ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
