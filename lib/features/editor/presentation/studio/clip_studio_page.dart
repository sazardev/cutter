import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/app/theme/app_tokens.dart'
    show WindowClass, windowClassOf;
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/presentation/clip_tools.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/playback_controller.dart';
import 'package:cutter/features/editor/presentation/preview_view.dart';
import 'package:cutter/features/editor/presentation/studio/studio_panels.dart';
import 'package:cutter/features/editor/presentation/studio/trim_bar.dart';
import 'package:cutter/features/editor/presentation/tools/transform_panel.dart';
import 'package:cutter/features/settings/presentation/appearance_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The tools of a clip editor.
enum StudioTab {
  /// Playback speed.
  speed(Icons.speed),

  /// How long an image shows.
  duration(Icons.timer_outlined),

  /// Position, size, turn and mirror.
  framing(Icons.crop_rotate),

  /// The kept part of the picture.
  crop(Icons.crop),

  /// Brightness, contrast, saturation and the automatic balance.
  adjust(Icons.tune),

  /// Colour looks.
  filters(Icons.auto_awesome_outlined),

  /// Volume and layer mute.
  volume(Icons.volume_up_outlined),

  /// Sound fades.
  fades(Icons.graphic_eq);

  const StudioTab(this.icon);

  /// Icon of the tab.
  final IconData icon;

  /// The tabs of a clip of [kind].
  static List<StudioTab> of(MediaKind kind) => switch (kind) {
        MediaKind.video => const [
            speed,
            framing,
            crop,
            adjust,
            filters,
            volume,
            fades,
          ],
        MediaKind.image => const [duration, framing, crop, adjust, filters],
        MediaKind.audio => const [volume, fades],
      };

  /// The localized name of the tab.
  String label(AppLocalizations l10n) => switch (this) {
        speed => l10n.speedTool,
        duration => l10n.durationTool,
        framing => l10n.transformTool,
        crop => l10n.cropTool,
        adjust => l10n.adjustTool,
        filters => l10n.filtersLabel,
        volume => l10n.volumeTool,
        fades => l10n.fadesTool,
      };

  /// The panel of the tab.
  Widget get panel => switch (this) {
        speed => const SpeedPanel(),
        duration => const ImageDurationPanel(),
        framing => const TransformPanel(),
        crop => const CropPanel(),
        adjust => const AdjustPanel(),
        filters => const FilterPicker(),
        volume => const VolumePanel(),
        fades => const FadesPanel(),
      };
}

/// Opens the editor of clip [clipId] over the project editor.
Future<void> openClipStudio(BuildContext context, String clipId) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => Consumer(
        builder: (context, ref, _) => Theme(
          data: ref.watch(editorThemeProvider),
          child: ClipStudioPage(clipId: clipId),
        ),
      ),
    ),
  );
}

/// One clip on its own: a video, an image or a sound, with its own preview
/// (only this clip plays), a trim bar over its whole source and the tools
/// that fit its kind. Every change is a normal project edit, saved at once
/// and undoable; Done goes back to the project at the same moment of the
/// clip.
class ClipStudioPage extends ConsumerStatefulWidget {
  /// Creates the editor of clip [clipId].
  const ClipStudioPage({required this.clipId, super.key});

  /// The clip edited.
  final String clipId;

  @override
  ConsumerState<ClipStudioPage> createState() => _ClipStudioPageState();
}

class _ClipStudioPageState extends ConsumerState<ClipStudioPage> {
  StudioTab? _tab;
  late final PlaybackController _playback;

  @override
  void initState() {
    super.initState();
    _playback = ref.read(playbackControllerProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(editorControllerProvider.notifier).selectClip(widget.clipId);
      _playback.isolate(widget.clipId);
    });
  }

  @override
  void dispose() {
    // Providers cannot change while the tree is being torn down: go back to
    // the whole project right after this frame.
    final playback = _playback;
    Future.microtask(() => playback.isolate(null));
    super.dispose();
  }

  String _title(AppLocalizations l10n, MediaKind kind) => switch (kind) {
        MediaKind.video => l10n.studioVideoTitle,
        MediaKind.image => l10n.studioImageTitle,
        MediaKind.audio => l10n.studioAudioTitle,
      };

  Future<void> _auto() async {
    final ok = await ref
        .read(editorControllerProvider.notifier)
        .autoAdjust(widget.clipId);
    if (ok) setState(() => _tab = StudioTab.adjust);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    ref.listen(editorControllerProvider, (previous, next) {
      final failure = next.valueOrNull?.failure;
      if (failure != null && failure != previous?.valueOrNull?.failure) {
        ref.read(editorControllerProvider.notifier).clearFailure();
      }
    });
    final editor = ref.watch(editorControllerProvider).valueOrNull;
    final clip = editor?.project.clipById(widget.clipId);
    final controller = ref.read(editorControllerProvider.notifier);
    if (editor == null || clip == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final tabs = StudioTab.of(clip.kind);
    final tab = _tab ?? tabs.first;
    final wide =
        windowClassOf(MediaQuery.sizeOf(context).width) != WindowClass.compact;
    final tools = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            children: [
              if (clip.kind != MediaKind.audio)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ActionChip(
                    avatar: const Icon(Icons.auto_fix_high, size: 18),
                    label: Text(l10n.autoAdjustAction),
                    onPressed: _auto,
                  ),
                ),
              if (clip.kind == MediaKind.video)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: FilterChip(
                    avatar: const Icon(Icons.fast_rewind_outlined, size: 18),
                    label: Text(l10n.reverseLabel),
                    selected: clip.reversed,
                    onSelected: (_) => controller.toggleReverse(),
                  ),
                ),
              for (final t in tabs)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ChoiceChip(
                    avatar: Icon(t.icon, size: 18),
                    label: Text(t.label(l10n)),
                    selected: t == tab,
                    onSelected: (_) {
                      HapticFeedback.selectionClick();
                      setState(() => _tab = t);
                    },
                  ),
                ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: tab.panel,
          ),
        ),
      ],
    );
    final preview = Column(
      children: [
        const Expanded(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.sm),
            child: PreviewView(),
          ),
        ),
        const TransportBar(),
        if (clip.kind != MediaKind.image) TrimBar(clip: clip),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(_title(l10n, clip.kind)),
        actions: [
          IconButton(
            tooltip: l10n.undoAction,
            icon: const Icon(Icons.undo),
            onPressed: editor.canUndo ? controller.undo : null,
          ),
          IconButton(
            tooltip: l10n.redoAction,
            icon: const Icon(Icons.redo),
            onPressed: editor.canRedo ? controller.redo : null,
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.doneAction),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  Expanded(child: preview),
                  SizedBox(
                    width: 380,
                    child: Material(
                      color: theme.colorScheme.surfaceContainerLow,
                      child: tools,
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  Expanded(flex: 6, child: preview),
                  Expanded(
                    flex: 5,
                    child: Material(
                      color: theme.colorScheme.surfaceContainer,
                      child: tools,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
