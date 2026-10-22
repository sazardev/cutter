import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/domain/animation_preset.dart';
import 'package:cutter/features/editor/domain/clip_settings_use_cases.dart';
import 'package:cutter/features/editor/domain/clip_transition.dart';
import 'package:cutter/features/editor/presentation/animation_preset_providers.dart';
import 'package:cutter/features/editor/presentation/clip_tools.dart'
    show AnimationPanel, EffectsPanel, filterIds, filterLabel;
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/tools/animation_presets.dart';
import 'package:cutter/features/editor/presentation/tools/gallery_actions.dart';
import 'package:cutter/features/editor/presentation/tools/gallery_item.dart';
import 'package:cutter/features/editor/presentation/tools/gallery_previews.dart';
import 'package:cutter/features/editor/presentation/tools/panel_kit.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _GalleryTab { transitions, effects, animations }

final _tabProvider = StateProvider.autoDispose<_GalleryTab>(
  (ref) => _GalleryTab.transitions,
);

/// Windows narrower than this show the cards in one scrolling row, to keep
/// the panel short and the timeline in view.
const double _compactWidth = 600;

/// Transitions and effects as cards with a still preview. A card is held and
/// dragged onto a clip of the timeline; a tap gives it to the selected clip.
/// Transitions ask where on the clip they go (start, end or both).
class EffectsGalleryPanel extends ConsumerWidget {
  /// Creates the panel.
  const EffectsGalleryPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final tab = ref.watch(_tabProvider);
    // Three tabs with an icon each do not fit a phone: the names go alone.
    final narrow = MediaQuery.sizeOf(context).width < _compactWidth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<_GalleryTab>(
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            ),
          ),
          segments: [
            ButtonSegment(
              value: _GalleryTab.transitions,
              icon: narrow ? null : const Icon(Icons.swap_horiz),
              label: Text(l10n.galleryTabTransitions),
            ),
            ButtonSegment(
              value: _GalleryTab.effects,
              icon: narrow ? null : const Icon(Icons.auto_awesome_outlined),
              label: Text(l10n.galleryTabEffects),
            ),
            ButtonSegment(
              value: _GalleryTab.animations,
              icon: narrow
                  ? null
                  : const Icon(Icons.auto_awesome_motion_outlined),
              label: Text(l10n.galleryTabAnimations),
            ),
          ],
          selected: {tab},
          onSelectionChanged: (value) =>
              ref.read(_tabProvider.notifier).state = value.first,
        ),
        PanelHint(l10n.galleryHint),
        const SizedBox(height: AppSpacing.sm),
        switch (tab) {
          _GalleryTab.transitions => const _TransitionsTab(),
          _GalleryTab.effects => const _EffectsTab(),
          _GalleryTab.animations => const _AnimationsTab(),
        },
      ],
    );
  }
}

class _TransitionsTab extends ConsumerWidget {
  const _TransitionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final editor = ref.watch(editorControllerProvider).valueOrNull;
    final clip = editor?.selectedClip;
    final layer = clip == null ? null : editor?.project.layerOfClip(clip.id);
    final before =
        layer == null || clip == null ? null : previousNeighbour(layer, clip);
    final current =
        before == null || clip == null ? null : transitionBetween(before, clip);
    final ms = ref.watch(galleryTransitionMsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GalleryCards(
          children: [
            GalleryCard(
              item: const TransitionItem(null),
              label: l10n.transitionNone,
            ),
            for (final kind in TransitionKind.values)
              GalleryCard(
                item: TransitionItem(kind),
                label: transitionLabel(l10n, kind),
                selected: current == kind,
              ),
          ],
        ),
        SliderTile(
          title: l10n.transitionDuration((ms / 1000).toStringAsFixed(1)),
          value: ms.toDouble(),
          min: minTransitionMs.toDouble(),
          max: maxTransitionMs.toDouble(),
          divisions: 18,
          onChanged: (v) =>
              ref.read(galleryTransitionMsProvider.notifier).state = v.round(),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          title: Text(l10n.transitionFadeSound),
          value: ref.watch(galleryFadeSoundProvider),
          onChanged: (value) =>
              ref.read(galleryFadeSoundProvider.notifier).state = value,
        ),
      ],
    );
  }
}

class _EffectsTab extends ConsumerWidget {
  const _EffectsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final clip = ref.watch(editorControllerProvider).valueOrNull?.selectedClip;
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(text, style: theme.textTheme.titleSmall),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(l10n.filtersLabel),
        GalleryCards(
          children: [
            GalleryCard(
              item: const FilterItem(null),
              label: l10n.filterNone,
              selected: clip != null && clip.filterId == null,
            ),
            for (final id in filterIds)
              GalleryCard(
                item: FilterItem(id),
                label: filterLabel(l10n, id),
                selected: clip?.filterId == id,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        heading(l10n.effectsLabel),
        GalleryCards(
          children: [
            for (final key in effectKeys)
              GalleryCard(
                item: EffectItem(key),
                label: effectLabel(l10n, key),
                selected: (clip?.adjustments[key] ?? 0) != 0,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        // Strength of each effect on the selected clip, live in the preview.
        const EffectsPanel(),
      ],
    );
  }
}

class _AnimationsTab extends ConsumerWidget {
  const _AnimationsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final clip = ref.watch(editorControllerProvider).valueOrNull?.selectedClip;
    final mine = ref.watch(userAnimationPresetsProvider).valueOrNull ??
        const <AnimationPreset>[];
    GalleryCard card(AnimationPreset preset, {bool deletable = false}) =>
        GalleryCard(
          item: AnimationPresetItem(preset),
          label: animationPresetName(l10n, preset),
          selected: clip != null && animationMatches(clip, preset),
          onDelete: deletable ? () => deleteAnimationPreset(ref, preset) : null,
          deleteLabel: l10n.animationPresetDelete,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GalleryCards(
          children: [
            card(noAnimationPreset),
            for (final preset in builtInAnimationPresets) card(preset),
          ],
        ),
        if (mine.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.md,
              bottom: AppSpacing.sm,
            ),
            child: Text(
              l10n.animationPresetYours,
              style: theme.textTheme.titleSmall,
            ),
          ),
          GalleryCards(
            children: [
              for (final preset in mine) card(preset, deletable: true),
            ],
          ),
        ],
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          title: Text(l10n.animationPresetWholeLayer),
          value: ref.watch(animationWholeLayerProvider),
          onChanged: (value) =>
              ref.read(animationWholeLayerProvider.notifier).state = value,
        ),
        if (clip != null && galleryAccepts(clip))
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => saveAnimationPresetAs(context, ref, clip),
              icon: const Icon(Icons.bookmark_add_outlined),
              label: Text(l10n.animationPresetSave),
            ),
          ),
        // The length of each side of the selected clip, live in the preview.
        const AnimationPanel(),
      ],
    );
  }
}

/// The cards in a scrolling row on narrow windows, wrapped on wide ones.
class GalleryCards extends StatelessWidget {
  /// Creates the row or wrap of [children].
  const GalleryCards({required this.children, super.key});

  /// The cards, in order.
  final List<GalleryCard> children;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < _compactWidth) {
      return SizedBox(
        height: GalleryCard.height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: children.length,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (_, i) => children[i],
        ),
      );
    }
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: children,
    );
  }
}

/// One card: the still preview over the name. Held, it lifts and follows
/// the finger; let go over a clip it gives the clip its content.
class GalleryCard extends ConsumerWidget {
  /// Creates a card for [item] named [label].
  const GalleryCard({
    required this.item,
    required this.label,
    this.selected = false,
    this.onDelete,
    this.deleteLabel,
    super.key,
  });

  /// What the card gives.
  final GalleryItem item;

  /// The name under the picture.
  final String label;

  /// Whether the selected clip already has what the card gives.
  final bool selected;

  /// Deletes the card's content, for the user's own presets; null for the
  /// ready-made ones.
  final VoidCallback? onDelete;

  /// What the delete button is called, for screen readers and hover.
  final String? deleteLabel;

  /// Width of a card: the picture and its padding.
  static const double width = GalleryPreview.width + 8;

  /// Height of a card: the picture, the name and the padding.
  static const double height = GalleryPreview.height + 8 + 32;

  Widget _face(BuildContext context, {bool lifted = false}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: width,
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color:
            selected ? scheme.secondaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(
          color: selected ? scheme.primary : Colors.transparent,
          width: 2,
        ),
        boxShadow: lifted
            ? [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GalleryPreview(item: item, live: lifted),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: 24,
            child: Center(
              child: Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final face = _face(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: LongPressDraggable<GalleryItem>(
        data: item,
        delay: const Duration(milliseconds: 150),
        hapticFeedbackOnStart: false,
        onDragStarted: HapticFeedback.mediumImpact,
        // The card is held by its middle, a little tilted: it feels picked up.
        dragAnchorStrategy: (_, __, ___) => const Offset(width / 2, 40),
        feedback: Transform.rotate(
          angle: -0.05,
          child: Transform.scale(
            scale: 1.1,
            child: Material(
              type: MaterialType.transparency,
              child: _face(context, lifted: true),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: face),
        child: Stack(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(AppRadii.medium),
              onTap: () => tapGalleryItem(context, ref, item),
              child: face,
            ),
            if (onDelete != null)
              Positioned(
                top: 0,
                right: 0,
                child: IconButton.filledTonal(
                  tooltip: deleteLabel,
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  icon: const Icon(Icons.close),
                  onPressed: onDelete,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
