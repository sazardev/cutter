import 'dart:io';

import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/data/engine_timeline.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/relink_media.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/import_flow.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether a file exists; tests replace it.
final fileExistsProvider = Provider<bool Function(String path)>(
  (ref) => (path) => File(path).existsSync(),
);

/// The sources of the open project's clips whose file is gone (moved or
/// deleted outside the app), as stored in the clips. Recomputed when the
/// clips change and by [recheckMissingMedia].
final missingSourcesProvider = FutureProvider.autoDispose<Set<String>>((
  ref,
) async {
  final uris = ref.watch(
    editorControllerProvider.select((editor) {
      final project = editor.valueOrNull?.project;
      if (project == null) return '';
      return ({
        for (final layer in project.layers)
          for (final clip in layer.clips) clip.sourceUri,
      }.toList()
            ..sort())
          .join('\n');
    }),
  );
  final exists = ref.read(fileExistsProvider);
  return {
    for (final uri in uris.split('\n'))
      if (uri.isNotEmpty && !exists(filePathOf(uri))) uri,
  };
});

/// Looks again at which files exist, e.g. when the app comes back to the
/// front.
void recheckMissingMedia(WidgetRef ref) =>
    ref.invalidate(missingSourcesProvider);

/// Asks for a file to replace the missing [oldUri] and relinks the clips to
/// it; says why when the file does not fit.
Future<void> relinkMissing(
  BuildContext context,
  WidgetRef ref,
  String oldUri,
  MediaKind? kind,
) async {
  final picked = await ref.read(mediaPickerProvider)(context, kind);
  if (picked == null || picked.isEmpty || !context.mounted) return;
  final check = await ref
      .read(editorControllerProvider.notifier)
      .relinkMedia(oldUri, picked.first);
  recheckMissingMedia(ref);
  if (check == RelinkCheck.ok || !context.mounted) return;
  final l10n = AppLocalizations.of(context)!;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.relinkTitle),
      content: Text(
        switch (check) {
          RelinkCheck.tooShort => l10n.relinkTooShort,
          RelinkCheck.wrongKind => l10n.relinkWrongKind,
          _ => l10n.relinkUnreadable,
        },
      ),
      actions: [
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.importReportClose),
        ),
      ],
    ),
  );
}

/// A banner above the timeline while files used by the project are
/// missing, with a way to point the clips at another file.
class MissingMediaBanner extends ConsumerStatefulWidget {
  /// Creates the banner.
  const MissingMediaBanner({super.key});

  @override
  ConsumerState<MissingMediaBanner> createState() => _MissingMediaBannerState();
}

class _MissingMediaBannerState extends ConsumerState<MissingMediaBanner>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may have restored or deleted files while the app was away.
    if (state == AppLifecycleState.resumed) recheckMissingMedia(ref);
  }

  @override
  Widget build(BuildContext context) {
    final missing = ref.watch(missingSourcesProvider).valueOrNull ?? const {};
    if (missing.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final first = missing.first;
    final project = ref.read(editorControllerProvider).valueOrNull?.project;
    MediaKind? kind;
    if (project != null) {
      for (final layer in project.layers) {
        for (final clip in layer.clips) {
          if (clip.sourceUri == first) kind = clip.kind;
        }
      }
    }
    return Semantics(
      liveRegion: true,
      child: Material(
        color: scheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(Icons.link_off, color: scheme.onErrorContainer),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  l10n.missingMediaBanner(missing.length),
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
              TextButton(
                onPressed: () => relinkMissing(context, ref, first, kind),
                child: Text(l10n.missingMediaFind),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
