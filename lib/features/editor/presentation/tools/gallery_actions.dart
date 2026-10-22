import 'dart:async';

import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/domain/clip_transition.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/tools/animation_presets.dart'
    show animationWholeLayerProvider;
import 'package:cutter/features/editor/presentation/tools/gallery_item.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks where on a clip a transition goes; null when dismissed.
Future<TransitionEdge?> askTransitionEdge(
  BuildContext context, {
  bool remove = false,
}) {
  final l10n = AppLocalizations.of(context)!;
  return showModalBottomSheet<TransitionEdge>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Text(
              remove ? l10n.galleryEdgeRemoveTitle : l10n.galleryEdgeTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final (edge, icon, label) in [
            (TransitionEdge.start, Icons.first_page, l10n.galleryEdgeStart),
            (TransitionEdge.end, Icons.last_page, l10n.galleryEdgeEnd),
            (TransitionEdge.both, Icons.unfold_more, l10n.galleryEdgeBoth),
          ])
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              onTap: () => Navigator.of(context).pop(edge),
            ),
        ],
      ),
    ),
  );
}

/// Gives [item] to [clip]: selects it so the preview shows the result, asks
/// where a transition goes, and does it as one edit.
Future<void> giveToClip(
  BuildContext context,
  WidgetRef ref,
  Clip clip,
  GalleryItem item,
) async {
  final controller = ref.read(editorControllerProvider.notifier);
  switch (item) {
    case TransitionItem(:final kind):
      final edge = await askTransitionEdge(context, remove: kind == null);
      if (edge == null) return;
      controller.selectClip(clip.id);
      unawaited(HapticFeedback.mediumImpact());
      if (kind == null) {
        await controller.removeTransition(edge: edge, clipId: clip.id);
      } else {
        await controller.applyTransition(
          kind,
          ref.read(galleryTransitionMsProvider),
          fadeSound: ref.read(galleryFadeSoundProvider),
          edge: edge,
          clipId: clip.id,
        );
      }
    case FilterItem(:final id):
      controller.selectClip(clip.id);
      unawaited(HapticFeedback.mediumImpact());
      await controller.setFilter(id);
    case AnimationPresetItem(:final preset):
      controller.selectClip(clip.id);
      unawaited(HapticFeedback.mediumImpact());
      await controller.applyAnimationPreset(
        preset,
        wholeLayer: ref.read(animationWholeLayerProvider),
      );
    case EffectItem(:final key):
      controller.selectClip(clip.id);
      unawaited(HapticFeedback.mediumImpact());
      await controller.setAdjustments({
        ...clip.adjustments,
        key: effectDefaultStrength,
      });
  }
}

/// A tap on a card: gives it to the selected clip, or says what is needed.
Future<void> tapGalleryItem(
  BuildContext context,
  WidgetRef ref,
  GalleryItem item,
) async {
  final l10n = AppLocalizations.of(context)!;
  final clip = ref.read(editorControllerProvider).valueOrNull?.selectedClip;
  final messenger = ScaffoldMessenger.of(context);
  if (clip == null || !galleryAccepts(clip)) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            clip == null ? l10n.galleryNeedsClip : l10n.galleryClipUnsupported,
          ),
        ),
      );
    return;
  }
  await giveToClip(context, ref, clip, item);
}
