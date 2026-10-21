import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/presentation/import_flow.dart';
import 'package:cutter/features/editor/presentation/time_format.dart';
import 'package:cutter/features/music/domain/music_pack.dart';
import 'package:cutter/features/music/presentation/music_library_controller.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The tracks of one installed pack; each places on the timeline from the
/// device's own copy, with no network.
class MusicPackPage extends ConsumerWidget {
  /// Creates the page for the installed pack [packId].
  const MusicPackPage({required this.packId, super.key});

  /// The pack to show.
  final String packId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final installed =
        ref.watch(musicLibraryProvider).valueOrNull?.installed[packId];
    if (installed == null) {
      return Scaffold(appBar: AppBar(title: Text(l10n.musicLibraryTitle)));
    }
    final source = installed.pack.source;
    final name = installed.pack.nameIn(
      Localizations.localeOf(context).languageCode,
    );
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.musicPackLicense(source.name, source.license),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (source.attribution != null)
                      Text(
                        l10n.musicPackCredit(source.attribution!),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              for (final track in installed.tracks)
                _TrackTile(path: installed.pathOf(track), track: track),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackTile extends ConsumerWidget {
  const _TrackTile({required this.path, required this.track});

  final String path;
  final MusicTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final details = [
      if (track.artist != null) track.artist!,
      if (track.durationMs > 0) formatTimecode(track.durationMs),
      if (track.bpm != null) l10n.musicTrackBpm(track.bpm!),
    ].join(' · ');
    return ListTile(
      leading: const Icon(Icons.graphic_eq),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: details.isEmpty ? null : Text(details),
      trailing: IconButton.filledTonal(
        tooltip: l10n.musicTrackAdd,
        icon: const Icon(Icons.add),
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          await importPaths(context, ref, [path]);
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.musicTrackAdded(track.title))),
          );
        },
      ),
    );
  }
}
