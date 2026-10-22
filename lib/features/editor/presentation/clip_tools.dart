import 'dart:async';

import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/capture/presentation/capture_panel.dart';
import 'package:cutter/features/capture/presentation/capture_providers.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/clip_settings_use_cases.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/presentation/clip_quick_bar.dart';
import 'package:cutter/features/editor/presentation/drawing/drawing_page.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/layout/editor_layout.dart';
import 'package:cutter/features/editor/presentation/playback_controller.dart';
import 'package:cutter/features/editor/presentation/studio/clip_studio_page.dart';
import 'package:cutter/features/editor/presentation/tools/animation_presets.dart';
import 'package:cutter/features/editor/presentation/tools/background_section.dart';
import 'package:cutter/features/editor/presentation/tools/canvas_panel.dart';
import 'package:cutter/features/editor/presentation/tools/diagnostics_panel.dart';
import 'package:cutter/features/editor/presentation/tools/editor_tool.dart';
import 'package:cutter/features/editor/presentation/tools/export_panel.dart';
import 'package:cutter/features/editor/presentation/tools/layout_panel.dart';
import 'package:cutter/features/editor/presentation/tools/media_bank_panel.dart';
import 'package:cutter/features/editor/presentation/tools/panel_kit.dart';
import 'package:cutter/features/editor/presentation/tools/project_settings_panel.dart';
import 'package:cutter/features/editor/presentation/tools/text_panel.dart';
import 'package:cutter/features/editor/presentation/tools/transform_panel.dart';
import 'package:cutter/features/editor/presentation/tools/transition_section.dart';
import 'package:cutter/features/editor/presentation/tools/versions_panel.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Identifiers of the filters the engine renders.
const List<String> filterIds = [
  'mono',
  'warm',
  'cool',
  'vintage',
  'sepia',
  'noir',
  'vivid',
  'fade',
  'cinema',
  'sunset',
  'invert',
];

/// The localized name of filter [id].
String filterLabel(AppLocalizations l10n, String id) => switch (id) {
      'mono' => l10n.filterMono,
      'warm' => l10n.filterWarm,
      'cool' => l10n.filterCool,
      'vintage' => l10n.filterVintage,
      'sepia' => l10n.filterSepia,
      'noir' => l10n.filterNoir,
      'vivid' => l10n.filterVivid,
      'fade' => l10n.filterFade,
      'cinema' => l10n.filterCinema,
      'sunset' => l10n.filterSunset,
      'invert' => l10n.filterInvert,
      _ => id,
    };

/// The localized name of animation [id].
String animationLabel(AppLocalizations l10n, String id) => switch (id) {
      'fade' => l10n.animationFade,
      'slide_left' => l10n.animationSlideLeft,
      'slide_right' => l10n.animationSlideRight,
      'slide_up' => l10n.animationSlideUp,
      'slide_down' => l10n.animationSlideDown,
      'zoom_in' => l10n.animationZoomIn,
      'zoom_out' => l10n.animationZoomOut,
      'spin' => l10n.animationSpin,
      'pop' => l10n.animationPop,
      _ => id,
    };

/// The editor actions the tools call; implemented by the editor page.
class EditorActions {
  /// Creates the action set.
  const EditorActions({
    required this.onAddMedia,
    required this.onAddLayer,
    required this.onSplit,
  });

  /// Picks media and places it where each kind belongs.
  final VoidCallback onAddMedia;

  /// Picks media and puts it on a new layer of its own kind at the
  /// playhead: a picture makes a picture layer, sound a sound layer.
  final VoidCallback onAddLayer;

  /// Splits the selected clip at the playhead.
  final VoidCallback onSplit;
}

/// The project tools, in the order the tool bars show them.
const List<EditorTool> projectTools = [
  EditorTool.media,
  EditorTool.capture,
  EditorTool.canvas,
  EditorTool.layout,
  EditorTool.versions,
  EditorTool.export,
  EditorTool.project,
  EditorTool.diagnostics,
];

/// Opens the editor of [clip]: the text tool for a text, the clip studio
/// for anything else.
void editClip(BuildContext context, WidgetRef ref, Clip clip) {
  if (clip.kind == MediaKind.text) {
    ref.read(activeToolProvider.notifier).state = EditorTool.text;
  } else if (clip.drawing != null) {
    unawaited(openDrawing(context, clipId: clip.id));
  } else {
    unawaited(openClipStudio(context, clip.id));
  }
}

/// The project tools this device shows: Capture only where there is a camera
/// and a microphone to capture with (phones and tablets).
List<EditorTool> visibleProjectTools(WidgetRef ref) {
  final capture = ref.watch(captureAvailableProvider);
  return [
    for (final tool in projectTools)
      if (tool != EditorTool.capture || capture) tool,
  ];
}

/// One labelled tool: an icon over a short label, at least 48dp square.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = onPressed == null
        ? scheme.onSurface.withValues(alpha: 0.38)
        : selected
            ? scheme.primary
            : scheme.onSurface;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 64, minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The docked tool bar under the timeline on narrow windows: the add and
/// project tools when nothing is selected, the clip tools otherwise. A tool
/// with settings opens its panel in place of the bar.
class EditorToolbar extends ConsumerWidget {
  /// Creates the toolbar.
  const EditorToolbar({required this.actions, super.key});

  /// What the buttons do.
  final EditorActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final editor = ref.watch(editorControllerProvider).valueOrNull;
    final clip = editor?.selectedClip;
    final controller = ref.read(editorControllerProvider.notifier);
    final playhead =
        ref.watch(playbackControllerProvider.select((p) => p.positionMs));
    void open(EditorTool tool) =>
        ref.read(activeToolProvider.notifier).state = tool;
    final detailsOpen =
        clip != null && ref.watch(clipDetailsProvider) == clip.id;
    // A tap on a clip shows only the short bar; More opens the long one.
    if (clip != null && !detailsOpen) {
      return Material(
        color: scheme.surfaceContainer,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Center(child: ClipQuickBar(actions: actions)),
          ),
        ),
      );
    }
    final List<Widget> tools;
    if (editor == null || clip == null) {
      tools = [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: FilledButton.icon(
            onPressed: actions.onAddMedia,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(l10n.addMediaAction),
          ),
        ),
        for (final tool in visibleProjectTools(ref))
          _ToolButton(
            icon: tool.icon,
            label: tool.label(l10n),
            onPressed: () => open(tool),
          ),
      ];
    } else {
      final visual = clip.kind != MediaKind.audio;
      // A text has no sound and no picture to filter or adjust.
      final colourable = visual && clip.kind != MediaKind.text;
      tools = [
        _ToolButton(
          icon: Icons.keyboard_arrow_down,
          label: l10n.doneAction,
          onPressed: () => ref.read(clipDetailsProvider.notifier).state = null,
        ),
        _ToolButton(
          icon: Icons.edit_outlined,
          label: l10n.editClipAction,
          onPressed: () => editClip(context, ref, clip),
        ),
        _ToolButton(
          icon: Icons.content_cut,
          label: l10n.splitAction,
          onPressed: controller.canSplitAt(playhead) ? actions.onSplit : null,
        ),
        _ToolButton(
          icon: Icons.delete_outline,
          label: l10n.deleteAction,
          onPressed: controller.deleteSelected,
        ),
        _ToolButton(
          icon: Icons.copy_outlined,
          label: l10n.duplicateAction,
          onPressed: controller.duplicateSelected,
        ),
        if (visual)
          _ToolButton(
            icon: EditorTool.transform.icon,
            label: EditorTool.transform.label(l10n),
            selected: !clip.transform.isIdentity,
            onPressed: () => open(EditorTool.transform),
          ),
        if (clip.kind != MediaKind.image && clip.kind != MediaKind.text)
          _ToolButton(
            icon: EditorTool.volume.icon,
            label: EditorTool.volume.label(l10n),
            selected: clip.volume < 1,
            onPressed: () => open(EditorTool.volume),
          ),
        if (colourable)
          _ToolButton(
            icon: EditorTool.filters.icon,
            label: EditorTool.filters.label(l10n),
            selected: clip.filterId != null,
            onPressed: () => open(EditorTool.filters),
          ),
        if (colourable)
          _ToolButton(
            icon: EditorTool.adjust.icon,
            label: EditorTool.adjust.label(l10n),
            selected: clip.adjustments.values.any((v) => v != 0),
            onPressed: () => open(EditorTool.adjust),
          ),
        if (clip.kind == MediaKind.video)
          _ToolButton(
            icon: Icons.fast_rewind_outlined,
            label: l10n.reverseLabel,
            selected: clip.reversed,
            onPressed: controller.toggleReverse,
          ),
      ];
    }
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          // A mouse or a trackpad drags the bar too, not only a finger.
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: PointerDeviceKind.values.toSet(),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Row(children: tools),
            ),
          ),
        ),
      ),
    );
  }
}

/// The content of [tool]'s panel.
Widget toolContent(EditorTool tool) => switch (tool) {
      EditorTool.volume => const VolumePanel(),
      EditorTool.filters => const FilterPicker(),
      EditorTool.adjust => const AdjustPanel(),
      EditorTool.transform => const TransformPanel(),
      EditorTool.text => const TextPanel(),
      EditorTool.media => const MediaBankPanel(),
      EditorTool.capture => const CapturePanel(),
      EditorTool.canvas => const CanvasPanel(),
      EditorTool.versions => const VersionsPanel(),
      EditorTool.export => const ExportPanel(),
      EditorTool.layout => const LayoutPanel(),
      EditorTool.project => const ProjectSettingsPanel(),
      EditorTool.diagnostics => const DiagnosticsPanel(),
    };

/// The open tool, or null when it needs a clip and none is selected.
EditorTool? visibleTool(WidgetRef ref) {
  final tool = ref.watch(activeToolProvider);
  if (tool == null || !tool.forClip) return tool;
  final clip = ref.watch(editorControllerProvider).valueOrNull?.selectedClip;
  return clip == null ? null : tool;
}

/// The bottom of the phone layout: the tool bar, or the open tool's panel
/// in its place, so the preview above stays visible and live.
class BottomToolArea extends ConsumerWidget {
  /// Creates the area.
  const BottomToolArea({required this.actions, super.key});

  /// What the tool bar buttons do.
  final EditorActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = visibleTool(ref);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.42;
    return AnimatedSize(
      duration: motionDurationOf(context),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: tool == null
          ? EditorToolbar(actions: actions)
          : Material(
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: SafeArea(
                top: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: ToolPanelFrame(tool: tool, child: toolContent(tool)),
                ),
              ),
            ),
    );
  }
}

/// 200 ms, or nothing when the user turned animations off.
Duration motionDurationOf(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);

/// The volume of the selected clip, and the mute of its layer.
class VolumePanel extends ConsumerStatefulWidget {
  /// Creates the volume panel.
  const VolumePanel({super.key});

  @override
  ConsumerState<VolumePanel> createState() => _VolumePanelState();
}

class _VolumePanelState extends ConsumerState<VolumePanel> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final editor = ref.watch(editorControllerProvider).valueOrNull;
    final clip = editor?.selectedClip;
    final layer = editor?.selectedLayer;
    if (clip == null || layer == null) return const SizedBox.shrink();
    final value = _dragging ?? clip.volume;
    final controller = ref.read(editorControllerProvider.notifier);
    final percent = (value * 100).round();
    return ToolSection(
      icon: Icons.volume_up_outlined,
      title: l10n.volumeTool,
      summary: layer.muted ? l10n.muteLayerAction : '$percent%',
      initiallyExpanded: true,
      children: [
        SliderTile(
          title: l10n.volumeLabel(percent),
          valueLabel: '$percent%',
          value: value,
          divisions: 20,
          onChanged: (v) => setState(() => _dragging = v),
          onChangeEnd: (v) async {
            setState(() => _dragging = null);
            await controller.setClipVolume(v);
          },
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          title: Text(l10n.muteLayerAction),
          value: layer.muted,
          onChanged: (muted) =>
              controller.setLayerMuted(layer.id, muted: muted),
        ),
      ],
    );
  }
}

/// The filters of the selected clip as large tiles; the preview shows the
/// choice at once.
class FilterPicker extends ConsumerWidget {
  /// Creates the filter picker.
  const FilterPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final clip = ref.watch(editorControllerProvider).valueOrNull?.selectedClip;
    if (clip == null) return const SizedBox.shrink();
    final controller = ref.read(editorControllerProvider.notifier);
    final options = <(String?, String, IconData)>[
      (null, l10n.filterNone, Icons.block),
      for (final id in filterIds) (id, filterLabel(l10n, id), _filterIcon(id)),
    ];
    final current = options.firstWhere(
      (o) => o.$1 == clip.filterId,
      orElse: () => options.first,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ToolSection(
          icon: Icons.auto_awesome_outlined,
          title: l10n.filtersLabel,
          summary: current.$2,
          initiallyExpanded: true,
          children: [
            for (final (id, label, icon) in options)
              OptionTile(
                icon: icon,
                title: label,
                selected: clip.filterId == id,
                onTap: () => controller.setFilter(id),
              ),
          ],
        ),
        const EffectsPanel(),
        const TransitionSection(),
        const AnimationPresets(),
        const AnimationPanel(),
        const BackgroundSection(),
      ],
    );
  }

  static IconData _filterIcon(String id) => switch (id) {
        'mono' => Icons.filter_b_and_w,
        'warm' => Icons.wb_sunny_outlined,
        'cool' => Icons.ac_unit,
        'vintage' => Icons.filter_vintage_outlined,
        'sepia' => Icons.brightness_5_outlined,
        'noir' => Icons.contrast,
        'vivid' => Icons.palette_outlined,
        'fade' => Icons.blur_on,
        'cinema' => Icons.movie_filter_outlined,
        'sunset' => Icons.wb_twilight,
        'invert' => Icons.invert_colors,
        _ => Icons.auto_awesome,
      };
}

/// How the selected clip comes in and goes out: an animation and a length
/// for each side. The length slider saves when let go.
class AnimationPanel extends ConsumerStatefulWidget {
  /// Creates the animation panel.
  const AnimationPanel({super.key});

  @override
  ConsumerState<AnimationPanel> createState() => _AnimationPanelState();
}

class _AnimationPanelState extends ConsumerState<AnimationPanel> {
  static const _defaultMs = 500;

  /// Length being dragged, by side (true is the entrance).
  final Map<bool, int> _dragged = {};

  /// Saves one side of the clip: [id] (null removes it) and [ms]; the other
  /// side stays as it is. A side with an id and no length gets the default.
  Future<void> _save(
    Clip clip, {
    required bool enter,
    String? id,
    int? ms,
    bool removed = false,
  }) async {
    final stored = enter ? clip.animInMs : clip.animOutMs;
    final side = (
      removed ? null : (id ?? (enter ? clip.animIn : clip.animOut)),
      ms ?? (stored > 0 ? stored : _defaultMs),
    );
    await ref.read(editorControllerProvider.notifier).setAnimation(
          animIn: enter ? side.$1 : clip.animIn,
          animInMs: enter ? side.$2 : clip.animInMs,
          animOut: enter ? clip.animOut : side.$1,
          animOutMs: enter ? clip.animOutMs : side.$2,
        );
    if (mounted) setState(_dragged.clear);
  }

  Widget _row(
    BuildContext context,
    Clip clip, {
    required bool enter,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final current = enter ? clip.animIn : clip.animOut;
    final stored = enter ? clip.animInMs : clip.animOutMs;
    final ms = _dragged[enter] ?? stored;
    final name = enter ? l10n.animationIn : l10n.animationOut;
    return ToolSection(
      icon: enter ? Icons.login : Icons.logout,
      title: name,
      summary:
          current == null ? l10n.animationNone : animationLabel(l10n, current),
      children: [
        OptionTile(
          title: l10n.animationNone,
          selected: current == null,
          onTap: () => _save(clip, enter: enter, removed: true),
        ),
        for (final id in clipAnimationIds)
          OptionTile(
            title: animationLabel(l10n, id),
            selected: current == id,
            onTap: () => _save(clip, enter: enter, id: id),
          ),
        if (current != null)
          SliderTile(
            title: l10n.animationDurationLabel(
              name,
              (ms / 1000).toStringAsFixed(1),
            ),
            value: ms.clamp(100, maxClipAnimationMs).toDouble(),
            min: 100,
            max: maxClipAnimationMs.toDouble(),
            divisions: 29,
            onChanged: (v) => setState(() => _dragged[enter] = v.round()),
            onChangeEnd: (v) => _save(clip, enter: enter, ms: v.round()),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final clip = ref.watch(editorControllerProvider).valueOrNull?.selectedClip;
    // A text clip has its own animation; sound has no picture.
    if (clip == null || clip.kind == MediaKind.audio || clip.text != null) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(context, clip, enter: true),
        _row(context, clip, enter: false),
      ],
    );
  }
}

/// Blur, vignette, grain, pixelate and sharpen of the selected clip. Moving
/// a slider updates the preview live; letting go saves.
class EffectsPanel extends ConsumerStatefulWidget {
  /// Creates the effects panel.
  const EffectsPanel({super.key});

  @override
  ConsumerState<EffectsPanel> createState() => _EffectsPanelState();
}

class _EffectsPanelState extends ConsumerState<EffectsPanel> {
  Map<String, double>? _draft;
  String? _clipId;

  String _name(AppLocalizations l10n, String key) => switch (key) {
        'blur' => l10n.effectBlur,
        'vignette' => l10n.effectVignette,
        'grain' => l10n.effectGrain,
        'pixelate' => l10n.effectPixelate,
        _ => l10n.effectSharpen,
      };

  Future<void> _commit() async {
    final draft = _draft;
    if (draft == null) return;
    await ref.read(editorControllerProvider.notifier).setAdjustments(draft);
    if (mounted) setState(() => _draft = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final clip = ref.watch(editorControllerProvider).valueOrNull?.selectedClip;
    if (clip == null) return const SizedBox.shrink();
    if (_clipId != clip.id) {
      _clipId = clip.id;
      _draft = null;
    }
    final values = _draft ?? clip.adjustments;
    final playback = ref.read(playbackControllerProvider.notifier);
    final active = effectKeys.where((key) => (values[key] ?? 0) != 0).length;
    return ToolSection(
      icon: Icons.blur_on,
      title: l10n.effectsLabel,
      summary: active == 0 ? null : '$active',
      children: [
        for (final key in effectKeys)
          SliderTile(
            title: _name(l10n, key),
            valueLabel: '${((values[key] ?? 0) * 100).round()}%',
            value: values[key] ?? 0,
            divisions: 20,
            onChanged: (v) {
              setState(() => _draft = {...values, key: v});
              playback.previewAdjustments(clip.id, _draft);
            },
            onChangeEnd: (_) => _commit(),
          ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          leading: const Icon(Icons.restart_alt),
          title: Text(l10n.resetAction),
          enabled: active != 0,
          onTap: () async {
            _draft = {
              ...values,
              for (final key in effectKeys) key: 0,
            };
            await _commit();
          },
        ),
      ],
    );
  }
}

/// Brightness, contrast and saturation of the selected clip. Moving a
/// slider updates the preview live; letting go saves.
class AdjustPanel extends ConsumerStatefulWidget {
  /// Creates the adjustments panel.
  const AdjustPanel({super.key});

  @override
  ConsumerState<AdjustPanel> createState() => _AdjustPanelState();
}

class _AdjustPanelState extends ConsumerState<AdjustPanel> {
  Map<String, double>? _draft;
  String? _clipId;

  static const _keys = colorAdjustmentKeys;

  String _label(AppLocalizations l10n, String key, double value) {
    final shown = (value * 100).round().toString();
    return switch (key) {
      'brightness' => l10n.brightnessLabel(shown),
      'contrast' => l10n.contrastLabel(shown),
      _ => l10n.saturationLabel(shown),
    };
  }

  Future<void> _commit(Clip clip) async {
    final draft = _draft;
    if (draft == null) return;
    await ref.read(editorControllerProvider.notifier).setAdjustments(draft);
    if (mounted) setState(() => _draft = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final clip = ref.watch(editorControllerProvider).valueOrNull?.selectedClip;
    if (clip == null) return const SizedBox.shrink();
    if (_clipId != clip.id) {
      _clipId = clip.id;
      _draft = null;
    }
    final values = _draft ?? clip.adjustments;
    final playback = ref.read(playbackControllerProvider.notifier);
    final untouched = _keys.every((key) => (values[key] ?? 0) == 0);
    return ToolSection(
      icon: Icons.tune,
      title: l10n.adjustmentsLabel,
      initiallyExpanded: true,
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          leading: const Icon(Icons.auto_fix_high),
          title: Text(l10n.autoAdjustAction),
          onTap: () =>
              ref.read(editorControllerProvider.notifier).autoAdjust(clip.id),
        ),
        for (final key in _keys)
          SliderTile(
            title: _label(l10n, key, values[key] ?? 0),
            value: values[key] ?? 0,
            min: adjustmentMin,
            divisions: 40,
            onChanged: (v) {
              setState(() => _draft = {...values, key: v});
              playback.previewAdjustments(clip.id, _draft);
            },
            onChangeEnd: (_) => _commit(clip),
          ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          leading: const Icon(Icons.restart_alt),
          title: Text(l10n.resetAction),
          enabled: !untouched,
          onTap: () async {
            _draft = {...values, for (final key in _keys) key: 0};
            await _commit(clip);
          },
        ),
      ],
    );
  }
}

/// The right panel of wide windows: everything about the selected clip.
/// It shows only while a clip is selected, so the preview gets the room
/// otherwise.
class ClipPropertiesPanel extends ConsumerWidget {
  /// Creates the panel.
  const ClipPropertiesPanel({required this.actions, super.key});

  /// What the buttons do.
  final EditorActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final editor = ref.watch(editorControllerProvider).valueOrNull;
    final clip = editor?.selectedClip;
    final controller = ref.read(editorControllerProvider.notifier);
    final playhead =
        ref.watch(playbackControllerProvider.select((p) => p.positionMs));
    if (clip == null) return const SizedBox.shrink();
    return Material(
      color: scheme.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.inspectorTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: l10n.doneAction,
                icon: const Icon(Icons.close),
                onPressed: () =>
                    ref.read(clipDetailsProvider.notifier).state = null,
              ),
            ],
          ),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _ToolButton(
                icon: Icons.edit_outlined,
                label: l10n.editClipAction,
                onPressed: () => editClip(context, ref, clip),
              ),
              _ToolButton(
                icon: Icons.content_cut,
                label: l10n.splitAction,
                onPressed:
                    controller.canSplitAt(playhead) ? actions.onSplit : null,
              ),
              if (clip.kind == MediaKind.video)
                _ToolButton(
                  icon: Icons.fast_rewind_outlined,
                  label: l10n.reverseLabel,
                  selected: clip.reversed,
                  onPressed: controller.toggleReverse,
                ),
              _ToolButton(
                icon: Icons.copy_outlined,
                label: l10n.duplicateAction,
                onPressed: controller.duplicateSelected,
              ),
              _ToolButton(
                icon: Icons.delete_outline,
                label: l10n.deleteAction,
                onPressed: controller.deleteSelected,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (clip.kind == MediaKind.text) const TextPanel(),
          if (clip.kind != MediaKind.audio) const TransformPanel(),
          if (clip.kind != MediaKind.image && clip.kind != MediaKind.text)
            const VolumePanel(),
          if (clip.kind != MediaKind.audio && clip.kind != MediaKind.text) ...[
            const FilterPicker(),
            const AdjustPanel(),
          ],
        ],
      ),
    );
  }
}

/// The side tool bar of wide windows: Add on top, then the project tools;
/// it folds to icons or unfolds with labels, and remembers which.
class EditorRail extends ConsumerWidget {
  /// Creates the rail.
  const EditorRail({
    required this.actions,
    this.forceCompact = false,
    super.key,
  });

  /// What Add does.
  final EditorActions actions;

  /// Shows icons only whatever the preference, to leave the preview room
  /// while a tool drawer and the clip panel are both open.
  final bool forceCompact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final windowWidth = MediaQuery.sizeOf(context).width;
    final expanded = !forceCompact &&
        ref.watch(
          editorLayoutProvider.select((p) => p.railExpandedAt(windowWidth)),
        );
    final active = ref.watch(activeToolProvider);
    final width = expanded ? 188.0 : 76.0;
    Widget item(EditorTool tool, {required bool labels}) {
      final selected = active == tool;
      final color =
          selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
      final icon = Icon(tool.icon, color: color);
      final label = Text(
        tool.label(l10n),
        // Icons-only labels may take two short lines ("Export / video").
        maxLines: labels ? 1 : 2,
        textAlign: labels ? TextAlign.start : TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style:
            (labels ? theme.textTheme.labelLarge : theme.textTheme.labelSmall)
                ?.copyWith(color: color),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 2,
        ),
        child: Semantics(
          button: true,
          selected: selected,
          label: tool.label(l10n),
          excludeSemantics: true,
          child: Tooltip(
            message: labels ? '' : tool.label(l10n),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.large),
              onTap: () {
                HapticFeedback.selectionClick();
                ref.read(activeToolProvider.notifier).state =
                    selected ? null : tool;
              },
              child: Ink(
                height: labels ? 48 : 64,
                decoration: BoxDecoration(
                  color: selected ? scheme.secondaryContainer : null,
                  borderRadius: BorderRadius.circular(AppRadii.large),
                ),
                child: labels
                    ? Row(
                        children: [
                          const SizedBox(width: AppSpacing.md),
                          icon,
                          const SizedBox(width: AppSpacing.md),
                          Expanded(child: label),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [icon, const SizedBox(height: 2), label],
                      ),
              ),
            ),
          ),
        ),
      );
    }

    return AnimatedContainer(
      duration: motionDurationOf(context),
      curve: Curves.easeOutCubic,
      width: width,
      color: scheme.surfaceContainer,
      child: SafeArea(
        right: false,
        // Labels follow the width actually laid out, so nothing overflows
        // while the bar animates.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final labels = constraints.maxWidth >= 140;
            return Column(
              children: [
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: labels
                      ? FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                          onPressed: actions.onAddMedia,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: Text(l10n.addMediaAction),
                        )
                      : IconButton.filled(
                          tooltip: l10n.addMediaAction,
                          iconSize: 28,
                          style: IconButton.styleFrom(
                            minimumSize: const Size(56, 56),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadii.large),
                            ),
                          ),
                          onPressed: actions.onAddMedia,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                        ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: ListView(
                    children: [
                      for (final tool in visibleProjectTools(ref))
                        item(tool, labels: labels),
                    ],
                  ),
                ),
                if (!forceCompact)
                  IconButton(
                    tooltip: expanded ? l10n.railCollapse : l10n.railExpand,
                    icon: Icon(
                      expanded
                          ? Icons.keyboard_double_arrow_left
                          : Icons.keyboard_double_arrow_right,
                    ),
                    onPressed: () => ref
                        .read(editorLayoutProvider.notifier)
                        .toggleRail(windowWidth),
                  ),
                const SizedBox(height: AppSpacing.sm),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The drawer next to the rail where a project tool opens on wide windows.
class ToolDrawer extends ConsumerWidget {
  /// Creates the drawer.
  const ToolDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(activeToolProvider);
    final show = tool != null && !tool.forClip;
    return AnimatedSize(
      duration: motionDurationOf(context),
      curve: Curves.easeOutCubic,
      alignment: Alignment.centerLeft,
      child: show
          ? SizedBox(
              width: 360,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ToolPanelFrame(tool: tool, child: toolContent(tool)),
                ),
              ),
            )
          : const SizedBox(width: 0, height: double.infinity),
    );
  }
}
