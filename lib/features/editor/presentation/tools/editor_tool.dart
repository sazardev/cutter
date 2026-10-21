import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The panels the editor can open. They open in place (above the tool bar
/// on phones, in the side panel on wide windows), never as dialogs, so the
/// preview stays visible and live.
enum EditorTool {
  /// Volume of the selected clip and mute of its layer.
  volume(Icons.volume_up_outlined, forClip: true),

  /// Filters of the selected clip.
  filters(Icons.auto_awesome_outlined, forClip: true),

  /// Brightness, contrast and saturation of the selected clip.
  adjust(Icons.tune, forClip: true),

  /// Position, scale, rotation, mirror, opacity and fit of the selected
  /// clip.
  transform(Icons.crop_rotate, forClip: true),

  /// The project's media bank: import once, place again and again.
  media(Icons.perm_media_outlined),

  /// The shape and frame rate of the canvas.
  canvas(Icons.aspect_ratio),

  /// Saving and restoring named versions.
  versions(Icons.history),

  /// Rendering the video.
  export(Icons.file_upload_outlined),

  /// Where the timeline and the tool bar sit.
  layout(Icons.dashboard_customize_outlined),

  /// The project's name, where its videos are saved, saving a restore point
  /// and deleting it.
  project(Icons.tune_outlined),

  /// Engine timings, memory and logs.
  diagnostics(Icons.monitor_heart_outlined);

  const EditorTool(this.icon, {this.forClip = false});

  /// Icon of the tool.
  final IconData icon;

  /// Whether the tool works on the selected clip and closes without one.
  final bool forClip;

  /// The localized name of the tool.
  String label(AppLocalizations l10n) => switch (this) {
        EditorTool.volume => l10n.volumeTool,
        EditorTool.filters => l10n.filtersLabel,
        EditorTool.adjust => l10n.adjustTool,
        EditorTool.transform => l10n.transformTool,
        EditorTool.media => l10n.mediaTool,
        EditorTool.canvas => l10n.canvasTool,
        EditorTool.versions => l10n.versionsTool,
        EditorTool.export => l10n.exportTitle,
        EditorTool.layout => l10n.layoutTool,
        EditorTool.project => l10n.projectTool,
        EditorTool.diagnostics => l10n.diagnosticsTool,
      };
}

/// The id of the clip whose full options are open, or null. A tap on a clip
/// only selects it and shows the short bar; a double tap, or More on that
/// bar, opens the full options (the side panel, or the long tool bar). It
/// closes by itself when another clip is selected, because the ids differ.
final clipDetailsProvider = StateProvider<String?>((ref) => null);

/// The open tool panel, or null when the tool bar shows.
final activeToolProvider = StateProvider<EditorTool?>((ref) => null);

/// A tool panel: a title row with a Done button over its content.
class ToolPanelFrame extends ConsumerWidget {
  /// Creates the frame for [tool] around [child].
  const ToolPanelFrame({required this.tool, required this.child, super.key});

  /// The tool shown.
  final EditorTool tool;

  /// The panel content.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.xs,
            0,
          ),
          child: Row(
            children: [
              Icon(tool.icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  tool.label(l10n),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: l10n.doneAction,
                icon: const Icon(Icons.check),
                onPressed: () =>
                    ref.read(activeToolProvider.notifier).state = null,
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}
