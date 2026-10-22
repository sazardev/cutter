import 'package:cutter/app/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// A collapsible group of controls: a card whose header (icon, title, a
/// short summary of what is set and an optional trailing widget) opens and
/// closes it. The tool panels are lists of these, so only what is being
/// worked on takes room.
class ToolSection extends StatelessWidget {
  /// Creates a section titled [title] around [children].
  const ToolSection({
    required this.title,
    required this.children,
    this.icon,
    this.summary,
    this.trailing,
    this.initiallyExpanded = false,
    super.key,
  });

  /// Name of the section.
  final String title;

  /// Icon before the title.
  final IconData? icon;

  /// What is set, in a few words, shown under the title while closed.
  final String? summary;

  /// A widget at the end of the header, such as a colour dot.
  final Widget? trailing;

  /// Whether the section starts open.
  final bool initiallyExpanded;

  /// The controls inside, one under the other.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.medium),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: Theme(
          // The tile draws no divider lines of its own.
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            shape: shape,
            collapsedShape: shape,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            leading: icon == null
                ? null
                : Icon(icon, color: scheme.onSurfaceVariant),
            title: Text(title, style: theme.textTheme.titleSmall),
            subtitle: summary == null
                ? null
                : Text(
                    summary!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
            trailing: trailing,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// A slider with its name and value above it, using the whole width: no
/// fixed label column, so long names and big thumbs never crowd each other.
class SliderTile extends StatelessWidget {
  /// Creates a slider tile.
  const SliderTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.valueLabel,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.onChangeEnd,
    super.key,
  });

  /// Name of the setting.
  final String title;

  /// What the value reads as, such as "120%"; shown at the end of the
  /// title line.
  final String? valueLabel;

  /// Current value.
  final double value;

  /// Lowest value.
  final double min;

  /// Highest value.
  final double max;

  /// Steps, or null for a continuous slider.
  final int? divisions;

  /// Called while the thumb moves.
  final ValueChanged<double> onChanged;

  /// Called when the thumb is let go.
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.bodyMedium)),
              if (valueLabel != null)
                Text(
                  valueLabel!,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ],
      ),
    );
  }
}

/// One choice of a list: an optional icon, a title, a line under it and a
/// check when it is the one in use. A whole row is the tap target.
class OptionTile extends StatelessWidget {
  /// Creates an option tile.
  const OptionTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.titleStyle,
    super.key,
  });

  /// Name of the choice.
  final String title;

  /// Style of the title, to show a font in itself.
  final TextStyle? titleStyle;

  /// A line under the title.
  final String? subtitle;

  /// Icon before the title.
  final IconData? icon;

  /// Whether it is the choice in use.
  final bool selected;

  /// Called when it is chosen.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      selected: selected,
      selectedTileColor: scheme.secondaryContainer.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      minVerticalPadding: AppSpacing.sm,
      leading: icon == null ? null : Icon(icon),
      title: Text(title, style: titleStyle),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: selected ? Icon(Icons.check, color: scheme.primary) : null,
      onTap: onTap,
    );
  }
}

/// A one-line explanation under a section's controls.
class PanelHint extends StatelessWidget {
  /// Creates a hint.
  const PanelHint(this.text, {super.key});

  /// The words.
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
