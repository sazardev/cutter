import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/library/presentation/videos_section.dart';
import 'package:cutter/features/music/domain/music_install_state.dart';
import 'package:cutter/features/music/domain/music_pack.dart';
import 'package:cutter/features/music/presentation/genre_icons.dart';
import 'package:cutter/features/music/presentation/music_failure_message.dart';
import 'package:cutter/features/music/presentation/music_library_controller.dart';
import 'package:cutter/features/music/presentation/music_pack_page.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The widest the list grows, so rows stay readable on a tablet.
const _maxContentWidth = 640.0;

/// The packs of music: download one once and its tracks stay on the device.
class MusicLibraryPage extends ConsumerWidget {
  /// Creates the page.
  const MusicLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final library = ref.watch(musicLibraryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.musicLibraryTitle)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: library.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => _Unavailable(
              onRetry: () => ref.invalidate(musicLibraryProvider),
            ),
            data: (state) => state.packs.isEmpty
                ? _Unavailable(
                    onRetry: () => ref.invalidate(musicLibraryProvider),
                  )
                : _PackList(state: state),
          ),
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.musicCatalogUnavailable,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.tonal(
              onPressed: onRetry,
              child: Text(l10n.musicRetry),
            ),
          ],
        ),
      ),
    );
  }
}

class _PackList extends ConsumerWidget {
  const _PackList({required this.state});

  final MusicLibraryState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final packs = state.packs;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      itemCount: packs.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              l10n.musicLibraryHint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        final pack = packs[i - 1];
        return _PackTile(pack: pack, packState: state.stateOf(pack.id));
      },
    );
  }
}

class _PackTile extends ConsumerWidget {
  const _PackTile({required this.pack, required this.packState});

  final MusicPack pack;
  final PackState packState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final controller = ref.read(musicLibraryProvider.notifier);
    final name = pack.nameIn(Localizations.localeOf(context).languageCode);
    final installed = packState is PackInstalled;
    final failed = packState is PackFailed ? packState as PackFailed : null;

    final status = switch (packState) {
      PackAvailable() => null,
      PackDownloading(:final progress) => progress == null
          ? l10n.musicPackDownloadingUnknown
          : l10n.musicPackDownloading((progress * 100).round()),
      PackUnpacking() => l10n.musicPackUnpacking,
      PackInstalled() => l10n.musicPackOffline,
      PackFailed(:final failure) => musicFailureMessage(l10n, failure),
    };

    final trailing = switch (packState) {
      PackAvailable() => FilledButton.tonal(
          onPressed: () => controller.install(pack),
          child: Text(l10n.musicPackDownload),
        ),
      PackDownloading(:final progress) => SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(value: progress, strokeWidth: 3),
        ),
      PackUnpacking() => const SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      PackInstalled() => IconButton(
          tooltip: l10n.musicPackRemove,
          onPressed: () => controller.remove(pack.id),
          icon: const Icon(Icons.delete_outline),
        ),
      PackFailed() => FilledButton.tonal(
          onPressed: () => controller.install(pack),
          child: Text(l10n.musicRetry),
        ),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: installed
            ? () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MusicPackPage(packId: pack.id),
                  ),
                )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(
                  dimension: 48,
                  child: Icon(
                    genreIcon(pack.genre),
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleMedium),
                    Text(
                      l10n.musicPackSummary(
                        pack.trackCount,
                        pack.bytes > 0 ? formatBytes(pack.bytes) : '–',
                        pack.source.name,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (status != null)
                      Text(
                        status,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: failed != null
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
