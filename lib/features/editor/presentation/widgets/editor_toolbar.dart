import 'package:cutter/app/theme/app_tokens.dart';
import 'package:cutter/features/editor/presentation/editor_controller.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Width of one action cell in the toolbar.
const double _actionWidth = 72;

/// Toolbar of editing actions: docked at the bottom on compact windows and
/// shown as a side column on larger ones.
class EditorToolbar extends StatelessWidget {
  /// Creates the toolbar; each callback runs when its action is tapped.
  const EditorToolbar({
    required this.controller,
    required this.onSplit,
    required this.onReverse,
    required this.onAddMedia,
    required this.onRecord,
    required this.onInspector,
    required this.onFilters,
    required this.onPresets,
    required this.onTemplates,
    this.windowClass = WindowClass.compact,
    super.key,
  });

  /// The editor state the actions read and listen to.
  final EditorController controller;

  /// Splits the selected clip at the playhead.
  final VoidCallback onSplit;

  /// Toggles reverse on the selected clip.
  final VoidCallback onReverse;

  /// Opens the media picker.
  final VoidCallback onAddMedia;

  /// Opens the record sheet.
  final VoidCallback onRecord;

  /// Opens the clip inspector.
  final VoidCallback onInspector;

  /// Opens the filters sheet.
  final VoidCallback onFilters;

  /// Opens the presets sheet.
  final VoidCallback onPresets;

  /// Opens the templates page.
  final VoidCallback onTemplates;

  /// Window class that decides between the docked and the side layout.
  final WindowClass windowClass;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDocked = windowClass == WindowClass.compact;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final actions = _actions(context);
        return Material(
          color: colors.surfaceContainer,
          child: isDocked
              ? SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(children: actions),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Column(children: actions),
                ),
        );
      },
    );
  }

  List<Widget> _actions(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasClip = controller.selectedClip != null;
    final isReversed = controller.selectedClip?.reversed ?? false;
    return [
      _ToolbarAction(
        icon: Icons.add_photo_alternate_outlined,
        label: l10n.actionAddMedia,
        onPressed: onAddMedia,
      ),
      _ToolbarAction(
        icon: Icons.mic_none,
        label: l10n.actionRecord,
        onPressed: onRecord,
      ),
      _ToolbarAction(
        icon: Icons.content_cut,
        label: l10n.actionSplit,
        onPressed: controller.canSplit ? onSplit : null,
      ),
      _ToolbarAction(
        icon: Icons.swap_horiz,
        label: l10n.actionReverse,
        selected: isReversed,
        onPressed: hasClip ? onReverse : null,
      ),
      _ToolbarAction(
        icon: Icons.tune,
        label: l10n.actionInspector,
        onPressed: hasClip ? onInspector : null,
      ),
      _ToolbarAction(
        icon: Icons.filter_b_and_w,
        label: l10n.actionFilters,
        onPressed: hasClip ? onFilters : null,
      ),
      _ToolbarAction(
        icon: Icons.bookmark_border,
        label: l10n.actionPresets,
        onPressed: onPresets,
      ),
      _ToolbarAction(
        icon: Icons.dashboard_customize_outlined,
        label: l10n.actionTemplates,
        onPressed: onTemplates,
      ),
    ];
  }
}

/// One toolbar action: an icon with a visible label and a 48dp minimum target.
class _ToolbarAction extends StatelessWidget {
  const _ToolbarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  static const Duration _selectionDuration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final enabled = onPressed != null;
    final contentColor = !enabled
        ? theme.disabledColor
        : selected
            ? colors.onSecondaryContainer
            : colors.onSurfaceVariant;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadii.large),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: _actionWidth,
            maxWidth: _actionWidth,
            minHeight: AppSizes.minTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: motionDuration(context, _selectionDuration),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? colors.secondaryContainer : null,
                    borderRadius: BorderRadius.circular(AppRadii.extraLarge),
                  ),
                  child: Icon(
                    selected ? Icons.check : icon,
                    color: contentColor,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: contentColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
