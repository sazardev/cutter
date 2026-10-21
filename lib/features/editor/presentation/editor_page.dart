import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/data/editor_dao.dart';
import 'package:cutter/features/editor/domain/clip.dart' as domain;
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/presentation/clip_inspector.dart';
import 'package:cutter/features/editor/presentation/editor_controller.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/failure_message.dart';
import 'package:cutter/features/editor/presentation/timeline_view.dart';
import 'package:cutter/l10n/app_localizations.dart';

const double _twoPaneBreakpoint = 600;
const double _inspectorPaneWidth = 360;
const double _compactInspectorHeight = 280;
const double _previewHeight = 160;
const double _previewAspectRatio = 16 / 9;
const int _playheadStepMs = 100;
const double _emptyMaxWidth = 360;
const String _audioKindName = 'audio';

/// The editor screen: preview placeholder, time label, timeline, inspector,
/// empty state and failure snackbars.
class EditorPage extends ConsumerStatefulWidget {
  /// Creates the editor screen.
  const EditorPage({super.key});

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  bool _noProject = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final dao = EditorDao(ref.read(appDatabaseProvider));
    final id = await dao.firstProjectId();
    if (!mounted) return;
    if (id == null) {
      setState(() => _noProject = true);
      return;
    }
    await ref.read(editorControllerProvider.notifier).load(id);
  }

  void _showFailure(EditorUiState? next) {
    final failure = next?.failure;
    if (failure == null) return;
    final l10n = AppLocalizations.of(context)!;
    final controller = ref.read(editorControllerProvider.notifier);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failureMessage(l10n, failure))));
    controller.clearFailure();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    ref.listen<AsyncValue<EditorUiState>>(
      editorControllerProvider,
      (previous, next) {
        final before = previous?.valueOrNull?.failure;
        final after = next.valueOrNull?.failure;
        if (after != null && after != before) _showFailure(next.valueOrNull);
      },
    );
    final state = ref.watch(editorControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.editorTitle)),
      body: SafeArea(child: _body(context, state)),
    );
  }

  Widget _body(BuildContext context, AsyncValue<EditorUiState> state) {
    if (_noProject) return const _EmptyState();
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(AppLocalizations.of(context)!.failureGeneric),
        ),
      ),
      data: (ui) {
        if (ui.project.layers.isEmpty) return const _EmptyState();
        return _EditorContent(ui: ui);
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _emptyMaxWidth),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Semantics(
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.emptyTitle,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.emptyBody,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorContent extends ConsumerWidget {
  const _EditorContent({required this.ui});

  final EditorUiState ui;

  ({domain.Clip clip, bool isAudio})? _selected(Project project) {
    final id = ui.selectedClipId;
    if (id == null) return null;
    for (final layer in project.layers) {
      for (final clip in layer.clips) {
        if (clip.id == id) {
          return (clip: clip, isAudio: layer.kind.name == _audioKindName);
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(editorControllerProvider.notifier);
    final selected = _selected(ui.project);
    final main = _MainPane(ui: ui, controller: controller);
    final inspector = ClipInspector(
      clip: selected?.clip,
      canSplit: controller.canSplit,
      filtersEnabled: selected != null && !selected.isAudio,
      onSplit: controller.splitAtPlayhead,
      onMoveEarlier: () => controller.nudgeSelected(-_playheadStepMs),
      onMoveLater: () => controller.nudgeSelected(_playheadStepMs),
      onReverseChanged: (_) => controller.toggleReverse(),
      onVolumeChanged: controller.setClipVolume,
      onFilterChanged: controller.setFilter,
      onAdjustmentChanged: controller.setAdjustment,
    );
    final wide = MediaQuery.sizeOf(context).width >= _twoPaneBreakpoint;
    if (wide) {
      return Row(
        children: [
          Expanded(child: main),
          SizedBox(width: _inspectorPaneWidth, child: inspector),
        ],
      );
    }
    return Column(
      children: [
        Expanded(child: main),
        SizedBox(height: _compactInspectorHeight, child: inspector),
      ],
    );
  }
}

class _MainPane extends StatelessWidget {
  const _MainPane({required this.ui, required this.controller});

  final EditorUiState ui;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: SizedBox(
            height: _previewHeight,
            child: Center(
              child: AspectRatio(
                aspectRatio: _previewAspectRatio,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppRadii.medium),
                  ),
                  child: Center(
                    child: Text(
                      l10n.previewPlaceholder,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: l10n.moveEarlierAction,
              icon: const Icon(Icons.chevron_left),
              onPressed: () => controller.seek(ui.playheadMs - _playheadStepMs),
            ),
            Semantics(
              liveRegion: false,
              child: Text(
                formatTimelineTime(ui.playheadMs),
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: l10n.moveLaterAction,
              icon: const Icon(Icons.chevron_right),
              onPressed: () => controller.seek(ui.playheadMs + _playheadStepMs),
            ),
          ],
        ),
        Expanded(
          child: TimelineView(
            project: ui.project,
            playheadMs: ui.playheadMs,
            selectedClipId: ui.selectedClipId,
            onSeek: controller.seek,
            onSelectClip: controller.selectClip,
          ),
        ),
      ],
    );
  }
}
