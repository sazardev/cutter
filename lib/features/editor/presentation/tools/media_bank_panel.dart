import 'dart:async';

import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/data/engine_timeline.dart';
import 'package:cutter/features/editor/domain/import_media.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/media_bank.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/import_flow.dart';
import 'package:cutter/features/editor/presentation/time_format.dart';
import 'package:cutter/features/library/presentation/library_previews.dart';
import 'package:cutter/features/music/presentation/music_library_page.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which bank the panel shows.
final _recentTabProvider = StateProvider.autoDispose<bool>((ref) => false);

/// Which kind the panel shows, or null for all.
final _bankFilterProvider =
    StateProvider.autoDispose<MediaKind?>((ref) => null);

/// The project's media bank: import files once (any kind, detected by the
/// engine), then tap one to place it where it belongs. Files imported into
/// other projects are a tab away.
class MediaBankPanel extends ConsumerWidget {
  /// Creates the panel.
  const MediaBankPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final project = ref.watch(editorControllerProvider).valueOrNull?.project;
    if (project == null) return const SizedBox.shrink();
    final recent = ref.watch(_recentTabProvider);
    final filter = ref.watch(_bankFilterProvider);
    final mine = ref.watch(projectMediaProvider(project.id)).valueOrNull ??
        const <MediaItem>[];
    final others = recent
        ? ref.watch(recentMediaProvider(project.id)).valueOrNull ??
            const <MediaItem>[]
        : const <MediaItem>[];
    final source = recent ? others : mine;
    final items = [
      for (final item in source)
        if (filter == null || item.kind == filter) item,
    ];
    final used = {
      for (final layer in project.layers)
        for (final clip in layer.clips) filePathOf(clip.sourceUri),
    };

    Future<void> place(MediaItem item, ImportPlacement placement) async {
      unawaited(HapticFeedback.selectionClick());
      if (recent) {
        // A recent file joins this project's bank as it is placed.
        await ref.read(mediaBankProvider).add([
          MediaItem(
            id: ref.read(idGeneratorProvider).next(),
            projectId: project.id,
            path: item.path,
            kind: item.kind,
            durationMs: item.durationMs,
            width: item.width,
            height: item.height,
            hasAudio: item.hasAudio,
            sizeBytes: item.sizeBytes,
            addedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        ]);
        ref.invalidate(projectMediaProvider(project.id));
      }
      if (!context.mounted) return;
      await placeFromBank(context, ref, [item], placement: placement);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(l10n.bankThisProject(mine.length)),
                  ),
                  ButtonSegment(value: true, label: Text(l10n.bankRecent)),
                ],
                selected: {recent},
                onSelectionChanged: (s) =>
                    ref.read(_recentTabProvider.notifier).state = s.single,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filledTonal(
              tooltip: l10n.musicLibraryTitle,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MusicLibraryPage(),
                ),
              ),
              icon: const Icon(Icons.library_music_outlined),
            ),
            IconButton.filled(
              tooltip: l10n.importAction,
              onPressed: () => pickAndImport(context, ref, toTimeline: false),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final (kind, label) in <(MediaKind?, String)>[
                (null, l10n.filterAllMedia),
                (MediaKind.video, l10n.layerKindVideo),
                (MediaKind.image, l10n.layerKindImage),
                (MediaKind.audio, l10n.layerKindAudio),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(label),
                    selected: filter == kind,
                    onSelected: (_) =>
                        ref.read(_bankFilterProvider.notifier).state = kind,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Text(
              recent ? l10n.bankRecentEmpty : l10n.bankEmpty,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else ...[
          Text(
            l10n.bankHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 120,
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 0.78,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => _BankTile(
              item: items[i],
              used: used.contains(items[i].path),
              onPlace: () => place(items[i], ImportPlacement.append),
              onOverlay: items[i].kind == MediaKind.audio
                  ? null
                  : () => place(items[i], ImportPlacement.overlay),
              onRemove: recent
                  ? null
                  : () async {
                      await ref.read(mediaBankProvider).remove(items[i].id);
                      ref.invalidate(projectMediaProvider(project.id));
                    },
            ),
          ),
        ],
      ],
    );
  }
}

class _BankTile extends ConsumerWidget {
  const _BankTile({
    required this.item,
    required this.used,
    required this.onPlace,
    required this.onOverlay,
    required this.onRemove,
  });

  final MediaItem item;
  final bool used;
  final VoidCallback onPlace;
  final VoidCallback? onOverlay;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final audio = item.kind == MediaKind.audio;
    final poster =
        audio ? null : ref.watch(videoPosterProvider(item.path)).valueOrNull;
    return Semantics(
      button: true,
      label: l10n.bankPlaceLabel(item.name),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        onTap: onPlace,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.medium),
                child: ColoredBox(
                  color: audio
                      ? scheme.secondaryContainer
                      : scheme.surfaceContainerHighest,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (poster != null)
                        RawImage(image: poster, fit: BoxFit.cover)
                      else
                        Icon(
                          audio ? Icons.graphic_eq : Icons.image_outlined,
                          size: 32,
                          color: audio
                              ? scheme.onSecondaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                      if (item.kind != MediaKind.image)
                        Positioned(
                          right: AppSpacing.xs,
                          bottom: AppSpacing.xs,
                          child: _Badge(
                            // Short sounds would all read 0:00.
                            text: formatTimecode(
                              item.durationMs,
                              tenths: item.durationMs < 10000,
                            ),
                          ),
                        ),
                      if (used)
                        Positioned(
                          left: AppSpacing.xs,
                          top: AppSpacing.xs,
                          child: Icon(
                            Icons.check_circle,
                            size: 16,
                            color: scheme.primary,
                            semanticLabel: l10n.bankUsed,
                          ),
                        ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: PopupMenuButton<VoidCallback>(
                          tooltip: l10n.moreActions,
                          icon: Icon(
                            Icons.more_vert,
                            size: 18,
                            color: scheme.onSurface,
                            shadows: [
                              Shadow(color: scheme.scrim, blurRadius: 4),
                            ],
                          ),
                          onSelected: (action) => action(),
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: onPlace,
                              child: Text(l10n.bankAddToTimeline),
                            ),
                            if (onOverlay != null)
                              PopupMenuItem(
                                value: onOverlay,
                                child: Text(l10n.bankAddAsOverlay),
                              ),
                            if (onRemove != null)
                              PopupMenuItem(
                                value: onRemove,
                                child: Text(l10n.bankRemove),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.scrim.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadii.small / 2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
