import 'package:cutter/app/theme/app_tokens.dart';
import 'package:flutter/material.dart';

const double _iconBadgeSize = 40;
const double _tileMinHeight = 64;

/// A rounded tonal badge with an icon, the leading mark of a section or row.
class SettingsIconBadge extends StatelessWidget {
  /// Creates a badge for [icon].
  const SettingsIconBadge(this.icon, {this.selected = false, super.key});

  /// The icon drawn inside the badge.
  final IconData icon;

  /// Whether the badge uses the strong primary color.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: _iconBadgeSize,
      height: _iconBadgeSize,
      decoration: BoxDecoration(
        color: selected ? scheme.primary : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Icon(
        icon,
        color: selected ? scheme.onPrimary : scheme.onPrimaryContainer,
      ),
    );
  }
}

/// A titled card that stacks its rows with dividers between them.
class SettingsGroup extends StatelessWidget {
  /// Creates a group of [children], with an optional small [title].
  const SettingsGroup({required this.children, this.title, super.key});

  /// Small heading above the card.
  final String? title;

  /// The rows, separated by dividers.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.none,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Semantics(
              header: true,
              child: Text(
                title!,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: AppSpacing.lg,
                    endIndent: AppSpacing.lg,
                    color: theme.colorScheme.outlineVariant,
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A row: optional icon, a title and one line of help on the left, a
/// control on the right.
class SettingsTile extends StatelessWidget {
  /// Creates a tile.
  const SettingsTile({
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
    super.key,
  });

  /// The setting's name.
  final String title;

  /// One line of help or the current value.
  final String? subtitle;

  /// Leading icon, drawn in a badge.
  final IconData? icon;

  /// The control at the end of the row.
  final Widget? trailing;

  /// Makes the whole row tappable.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _tileMinHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                SettingsIconBadge(icon!),
                const SizedBox(width: AppSpacing.lg),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.md),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A row whose control is wide: title and help on top, [child] below.
class SettingsBlock extends StatelessWidget {
  /// Creates a block.
  const SettingsBlock({
    required this.title,
    required this.help,
    required this.child,
    super.key,
  });

  /// The setting's name.
  final String title;

  /// One line of help.
  final String help;

  /// The wide control.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            help,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}
