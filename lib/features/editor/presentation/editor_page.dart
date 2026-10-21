import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/app/theme/app_tokens.dart'
    show WindowClass, windowClassOf;
import 'package:cutter/features/editor/domain/import_media.dart';
import 'package:cutter/features/editor/presentation/checkpoint_labels.dart';
import 'package:cutter/features/editor/presentation/clip_quick_bar.dart';
import 'package:cutter/features/editor/presentation/clip_tools.dart';
import 'package:cutter/features/editor/presentation/editor_controller.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/import_flow.dart';
import 'package:cutter/features/editor/presentation/layout/editor_layout.dart';
import 'package:cutter/features/editor/presentation/layout/editor_split.dart';
import 'package:cutter/features/editor/presentation/missing_media.dart';
import 'package:cutter/features/editor/presentation/playback_controller.dart';
import 'package:cutter/features/editor/presentation/preview_view.dart';
import 'package:cutter/features/editor/presentation/project_title.dart';
import 'package:cutter/features/editor/presentation/timeline/timeline_view.dart';
import 'package:cutter/features/editor/presentation/tools/editor_tool.dart';
import 'package:cutter/features/editor/presentation/tools/export_panel.dart';
import 'package:cutter/features/settings/presentation/appearance_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double _emptyMaxWidth = 360;

/// The editor for one project. Always dark, as video work needs a neutral
/// surround to judge colour. Phones stack preview, timeline and a tool bar;
/// wide windows add a side panel with every clip property.
class EditorPage extends ConsumerStatefulWidget {
  /// Creates the editor screen for the project with [projectId].
  const EditorPage({
    required this.projectId,
    this.initialImport = const [],
    super.key,
  });

  /// The id of the project this screen edits.
  final String projectId;

  /// Files imported as soon as the project opens (editing a rendered video
  /// again starts this way).
  final List<String> initialImport;

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  final GlobalKey<TimelineViewState> _timeline = GlobalKey();
  BuildContext? _themedContext;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// The names of the automatic restore points, in the screen's language.
  CheckpointLabels _checkpointLabels() {
    final l10n = AppLocalizations.of(context)!;
    String clock(DateTime at) => TimeOfDay.fromDateTime(at).format(context);
    return CheckpointLabels(
      start: l10n.checkpointStart,
      auto: (at) => l10n.checkpointAuto(clock(at)),
      beforeRestore: l10n.checkpointBeforeRestore,
    );
  }

  Future<void> _load() async {
    try {
      await ref.read(editorControllerProvider.notifier).load(
            widget.projectId,
            labels: _checkpointLabels(),
          );
      if (widget.initialImport.isNotEmpty && mounted) {
        await importPaths(
          _themedContext ?? context,
          ref,
          widget.initialImport,
        );
      }
    } on Object catch (error, stackTrace) {
      if (!mounted) return;
      ref
          .read(editorControllerProvider.notifier)
          .reportError(error, stackTrace);
    }
  }

  /// A rejected edit simply does not apply; nothing covers the screen.
  void _dropFailure(EditorUiState? next) {
    if (next?.failure == null) return;
    ref.read(editorControllerProvider.notifier).clearFailure();
  }

  /// The actions, bound to [themed]: a context under the editor's dark
  /// theme, so dialogs and sheets they open are dark too.
  EditorActions _actionsFor(BuildContext themed) => EditorActions(
        onAddMedia: () => pickAndImport(themed, ref),
        onAddLayer: () => pickAndImport(
          themed,
          ref,
          placement: ImportPlacement.overlay,
        ),
        onSplit: _split,
      );

  void _split() {
    final playhead = ref.read(playbackControllerProvider).positionMs;
    ref.read(editorControllerProvider.notifier).splitAt(playhead);
  }

  Future<void> _quickSave(BuildContext themed) async {
    final l10n = AppLocalizations.of(themed)!;
    final editor = ref.read(editorControllerProvider).valueOrNull;
    if (editor == null) return;
    final versions =
        await ref.read(projectVersionsProvider(editor.project.id).future);
    await ref
        .read(editorControllerProvider.notifier)
        .saveVersion(l10n.defaultVersionName(versions.length + 1));
  }

  void _escape() {
    if (ref.read(previewModeProvider)) {
      ref.read(previewModeProvider.notifier).state = false;
    } else if (ref.read(activeToolProvider) != null) {
      ref.read(activeToolProvider.notifier).state = null;
    } else if (ref.read(clipDetailsProvider) != null) {
      ref.read(clipDetailsProvider.notifier).state = null;
    } else {
      ref.read(editorControllerProvider.notifier).selectClip(null);
    }
  }

  Map<SingleActivator, VoidCallback> _shortcuts(BuildContext themed) {
    final editor = ref.read(editorControllerProvider.notifier);
    final playback = ref.read(playbackControllerProvider.notifier);
    void open(EditorTool tool) =>
        ref.read(activeToolProvider.notifier).state = tool;
    return {
      const SingleActivator(LogicalKeyboardKey.space): playback.toggle,
      const SingleActivator(LogicalKeyboardKey.keyS): _split,
      const SingleActivator(LogicalKeyboardKey.delete): editor.deleteSelected,
      const SingleActivator(LogicalKeyboardKey.backspace):
          editor.deleteSelected,
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
          editor.undo,
      const SingleActivator(
        LogicalKeyboardKey.keyZ,
        control: true,
        shift: true,
      ): editor.redo,
      const SingleActivator(LogicalKeyboardKey.keyY, control: true):
          editor.redo,
      const SingleActivator(LogicalKeyboardKey.keyD, control: true):
          editor.duplicateSelected,
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
          _quickSave(themed),
      const SingleActivator(LogicalKeyboardKey.keyE, control: true): () =>
          open(EditorTool.export),
      const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
          pickAndImport(themed, ref),
      const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
          open(EditorTool.media),
      const SingleActivator(LogicalKeyboardKey.backslash, control: true): () =>
          ref
              .read(editorLayoutProvider.notifier)
              .toggleRail(MediaQuery.sizeOf(context).width),
      const SingleActivator(LogicalKeyboardKey.keyT): () =>
          open(EditorTool.transform),
      const SingleActivator(LogicalKeyboardKey.keyF): () => ref
          .read(previewModeProvider.notifier)
          .update((previewing) => !previewing),
      const SingleActivator(LogicalKeyboardKey.home): () => playback.seek(0),
      const SingleActivator(LogicalKeyboardKey.end): () =>
          playback.seek(playback.durationMs),
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
          playback.stepFrame(forward: false),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
          playback.stepFrame(forward: true),
      const SingleActivator(LogicalKeyboardKey.equal): () =>
          _timeline.currentState?.zoomIn(),
      const SingleActivator(LogicalKeyboardKey.minus): () =>
          _timeline.currentState?.zoomOut(),
      const SingleActivator(LogicalKeyboardKey.escape): _escape,
    };
  }

  @override
  Widget build(BuildContext context) {
    ref
      ..listen<AsyncValue<EditorUiState>>(editorControllerProvider,
          (previous, next) {
        final before = previous?.valueOrNull?.failure;
        final after = next.valueOrNull?.failure;
        if (after != null && after != before) _dropFailure(next.valueOrNull);
      })
      // Keep the preview and a running export alive for as long as the
      // editor is open.
      ..watch(playbackControllerProvider.select((p) => p.textureId))
      ..watch(exportControllerProvider.select((e) => e.phase));
    final state = ref.watch(editorControllerProvider);
    return Theme(
      data: ref.watch(editorThemeProvider),
      child: Builder(
        builder: (context) {
          _themedContext = context;
          return _EditorShortcuts(
            bindings: _shortcuts(context),
            child: Focus(
              autofocus: true,
              child: PopScope(
                // Back leaves preview mode or closes a panel before the editor.
                canPop: !ref.watch(previewModeProvider) &&
                    ref.watch(activeToolProvider) == null,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) _escape();
                },
                child: ref.watch(previewModeProvider)
                    ? const _PreviewModeScaffold()
                    : Scaffold(
                        appBar: _EditorAppBar(
                          projectId: widget.projectId,
                          onOpenTool: (tool) => ref
                              .read(activeToolProvider.notifier)
                              .state = tool,
                        ),
                        body: SafeArea(child: _body(context, state)),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, AsyncValue<EditorUiState> state) {
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _LoadError(onRetry: _load),
      data: (ui) {
        // The controller outlives the page: until this project is loaded it
        // still holds the previous one.
        if (ui.project.id != widget.projectId) {
          return const Center(child: CircularProgressIndicator());
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final actions = _actionsFor(context);
            final windowClass = windowClassOf(constraints.maxWidth);
            // A phone held sideways is as wide as a tablet but short: it
            // gets the rail too.
            final wide = windowClass == WindowClass.expanded ||
                (windowClass == WindowClass.medium &&
                    constraints.maxWidth > constraints.maxHeight);
            return wide
                ? _wide(actions, constraints)
                : _compact(actions, constraints);
          },
        );
      },
    );
  }

  Widget _timelineView(EditorActions actions) => Column(
        children: [
          const MissingMediaBanner(),
          Expanded(
            child: TimelineView(
              key: _timeline,
              onAddMedia: actions.onAddMedia,
              onAddLayer: actions.onAddLayer,
            ),
          ),
        ],
      );

  /// Phones held upright: preview, transport and timeline in a column (the
  /// timeline above or below), the tool bar or an open panel at the bottom.
  Widget _compact(EditorActions actions, BoxConstraints constraints) {
    final importing =
        ref.watch(editorControllerProvider).valueOrNull?.importing ?? false;
    final top =
        ref.watch(editorLayoutProvider).timeline == TimelinePosition.top;
    return Column(
      children: [
        if (importing) const LinearProgressIndicator(),
        Expanded(
          child: EditorSplit(
            position: top ? TimelinePosition.top : TimelinePosition.bottom,
            preview: const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                0,
              ),
              child: PreviewView(),
            ),
            transport: const TransportBar(withHistory: true),
            timeline: _timelineView(actions),
          ),
        ),
        BottomToolArea(actions: actions),
      ],
    );
  }

  /// Tablets, desktops and phones held sideways: the side tool bar and its
  /// drawer on the left, the preview and the timeline in the chosen
  /// arrangement, and the clip panel on the right while a clip is selected.
  Widget _wide(EditorActions actions, BoxConstraints constraints) {
    final importing =
        ref.watch(editorControllerProvider).valueOrNull?.importing ?? false;
    final selected =
        ref.watch(editorControllerProvider).valueOrNull?.selectedClip;
    final hasClip =
        selected != null && ref.watch(clipDetailsProvider) == selected.id;
    final position = ref.watch(editorLayoutProvider).timeline;
    final tool = ref.watch(activeToolProvider);
    final drawerOpen = tool != null && !tool.forClip;
    final short = constraints.maxHeight < 520;
    Widget content = EditorSplit(
      position: position,
      preview: Padding(
        padding: EdgeInsets.all(short ? AppSpacing.sm : AppSpacing.lg),
        child: const PreviewView(),
      ),
      transport: const TransportBar(),
      timeline: _timelineView(actions),
    );
    // A selected clip shows only a short bar floating over the timeline; the
    // full options come with a double tap or More.
    content = Stack(
      children: [
        content,
        Positioned(
          left: 0,
          right: 0,
          bottom: AppSpacing.md,
          child: IgnorePointer(
            ignoring: selected == null || hasClip,
            child: AnimatedOpacity(
              duration: motionDurationOf(context),
              opacity: selected == null || hasClip ? 0 : 1,
              child: Center(child: ClipQuickBar(actions: actions)),
            ),
          ),
        ),
      ],
    );
    return Column(
      children: [
        if (importing) const LinearProgressIndicator(),
        Expanded(
          child: Row(
            children: [
              EditorRail(
                actions: actions,
                forceCompact: drawerOpen && hasClip,
              ),
              const ToolDrawer(),
              Expanded(child: content),
              AnimatedSize(
                duration: motionDurationOf(context),
                curve: Curves.easeOutCubic,
                child: hasClip
                    ? SizedBox(
                        width: 340,
                        child: ClipPropertiesPanel(actions: actions),
                      )
                    : const SizedBox(width: 0, height: double.infinity),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditorAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const _EditorAppBar({required this.projectId, required this.onOpenTool});

  final String projectId;
  final ValueChanged<EditorTool> onOpenTool;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final ui = ref.watch(editorControllerProvider).valueOrNull;
    final loaded = ui != null && ui.project.id == projectId;
    final controller = ref.read(editorControllerProvider.notifier);
    final export = ref.watch(exportControllerProvider);
    final compact =
        windowClassOf(MediaQuery.sizeOf(context).width) == WindowClass.compact;
    return AppBar(
      titleSpacing: 0,
      title: Row(
        children: [
          Flexible(
            child: loaded
                ? ProjectTitle(name: ui.project.name)
                : Text(l10n.editorTitle, overflow: TextOverflow.ellipsis),
          ),
          if (loaded) ...[
            const SizedBox(width: AppSpacing.sm),
            Tooltip(
              message: l10n.statusSavedBody,
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.cloud_done_outlined, size: 16),
                label: Text(
                  l10n.statusSaved,
                  style: theme.textTheme.labelSmall,
                ),
                onPressed: () => onOpenTool(EditorTool.versions),
              ),
            ),
          ],
        ],
      ),
      actions: [
        // Narrow windows carry undo and redo in the transport bar.
        if (!compact) ...[
          IconButton(
            tooltip: l10n.undoAction,
            icon: const Icon(Icons.undo),
            onPressed: loaded && ui.canUndo ? controller.undo : null,
          ),
          IconButton(
            tooltip: l10n.redoAction,
            icon: const Icon(Icons.redo),
            onPressed: loaded && ui.canRedo ? controller.redo : null,
          ),
        ],
        const SizedBox(width: AppSpacing.xs),
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.sm),
          child: export.phase == ExportPhase.running
              ? ActionChip(
                  avatar: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: export.progress,
                    ),
                  ),
                  label: Text('${(export.progress * 100).round()}%'),
                  onPressed: () => onOpenTool(EditorTool.export),
                )
              : FilledButton(
                  onPressed: loaded && ui.project.durationMs > 0
                      ? () {
                          ref.read(playbackControllerProvider.notifier).pause();
                          onOpenTool(EditorTool.export);
                        }
                      : null,
                  child: Text(l10n.exportAction),
                ),
        ),
      ],
    );
  }
}

/// Preview mode: only the picture, a scrub bar and the transport.
class _PreviewModeScaffold extends ConsumerWidget {
  const _PreviewModeScaffold();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.scrim,
      body: const SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: PreviewView(interactive: false),
              ),
            ),
            PreviewScrubber(),
            TransportBar(),
            SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

/// Single keys (S, Space, Delete…) act on the editor except while a text
/// field has focus: then they are left to the field.
class _EditorShortcuts extends StatelessWidget {
  const _EditorShortcuts({required this.bindings, required this.child});

  final Map<SingleActivator, VoidCallback> bindings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        for (final activator in bindings.keys) activator: _KeyIntent(activator),
      },
      child: Actions(
        actions: {_KeyIntent: _KeyAction(bindings)},
        child: child,
      ),
    );
  }
}

class _KeyIntent extends Intent {
  const _KeyIntent(this.activator);

  final SingleActivator activator;
}

class _KeyAction extends Action<_KeyIntent> {
  _KeyAction(this.bindings);

  final Map<SingleActivator, VoidCallback> bindings;

  static bool get _typing {
    final focused = FocusManager.instance.primaryFocus?.context;
    return focused != null &&
        (focused.widget is EditableText ||
            focused.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  @override
  bool isEnabled(_KeyIntent intent) {
    final a = intent.activator;
    final plain = !a.control && !a.meta && !a.alt;
    return !(plain && _typing && a.trigger != LogicalKeyboardKey.escape);
  }

  @override
  Object? invoke(_KeyIntent intent) {
    bindings[intent.activator]?.call();
    return null;
  }
}

/// The state shown when the project cannot be read from the local database:
/// what failed, and the action that retries it.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _emptyMaxWidth),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.loadErrorTitle,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.loadErrorBody,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(onPressed: onRetry, child: Text(l10n.retryAction)),
            ],
          ),
        ),
      ),
    );
  }
}
