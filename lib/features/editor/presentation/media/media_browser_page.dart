import 'dart:async';
import 'dart:io';

import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/presentation/media/media_formats.dart';
import 'package:cutter/features/library/presentation/library_previews.dart';
import 'package:cutter/features/settings/presentation/appearance_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The folder the browser opened last, so the next pick starts there.
String? _lastFolder;

/// A media picker inside the app, for desktops without a system file portal:
/// folder shortcuts, a grid of folders and media files only (pre-filtered
/// by type), real thumbnails, search and several files at once. Pops with
/// the chosen paths, or null.
class MediaBrowserPage extends ConsumerStatefulWidget {
  /// Creates the browser; [initialFilter] narrows it to one kind, and
  /// [initialFolder] replaces the last folder visited (or home).
  const MediaBrowserPage({
    this.initialFilter,
    this.initialFolder,
    this.chooseFolder = false,
    super.key,
  });

  /// Whether it picks one folder instead of files: only folders are shown
  /// and the page pops with the folder it is in.
  final bool chooseFolder;

  /// The kind shown at first, or null for all media.
  final MediaKind? initialFilter;

  /// The folder shown at first, if given.
  final String? initialFolder;

  @override
  ConsumerState<MediaBrowserPage> createState() => _MediaBrowserPageState();
}

class _Entry {
  const _Entry(this.path, {required this.isFolder, this.kind});

  final String path;
  final bool isFolder;
  final MediaKind? kind;

  String get name => path.split(Platform.pathSeparator).last;
}

class _MediaBrowserPageState extends ConsumerState<MediaBrowserPage> {
  late String _folder;
  MediaKind? _filter;
  String _query = '';
  List<_Entry> _entries = const [];
  bool _loading = true;
  final List<String> _picked = [];

  static String get _home => Platform.environment['HOME'] ?? '/';

  List<(IconData, String, String)> _places(AppLocalizations l10n) {
    final sep = Platform.pathSeparator;
    return [
      (Icons.home_outlined, l10n.placeHome, _home),
      (Icons.movie_outlined, l10n.placeVideos, '$_home${sep}Videos'),
      (Icons.image_outlined, l10n.placePictures, '$_home${sep}Pictures'),
      (Icons.music_note_outlined, l10n.placeMusic, '$_home${sep}Music'),
      (Icons.download_outlined, l10n.placeDownloads, '$_home${sep}Downloads'),
      (
        Icons.desktop_windows_outlined,
        l10n.placeDesktop,
        '$_home${sep}Desktop'
      ),
    ].where((p) => Directory(p.$3).existsSync()).toList();
  }

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
    _folder = widget.initialFolder ??
        (_lastFolder != null && Directory(_lastFolder!).existsSync()
            ? _lastFolder!
            : _home);
    unawaited(_open(_folder));
  }

  Future<void> _open(String folder) async {
    setState(() {
      _folder = folder;
      _loading = true;
    });
    _lastFolder = folder;
    final entries = <_Entry>[];
    try {
      await for (final e in Directory(folder).list(followLinks: false)) {
        final name = e.path.split(Platform.pathSeparator).last;
        if (name.startsWith('.')) continue;
        if (e is Directory) {
          entries.add(_Entry(e.path, isFolder: true));
        } else if (e is File) {
          final kind = kindByName(e.path);
          if (kind != null) {
            entries.add(_Entry(e.path, isFolder: false, kind: kind));
          }
        }
      }
    } on FileSystemException {
      // An unreadable folder shows as empty.
    }
    entries.sort((a, b) {
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    if (!mounted || folder != _folder) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  void _toggle(String path) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_picked.remove(path)) _picked.add(path);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Dark like the editor it opens from.
    return Theme(
      data: ref.watch(editorThemeProvider),
      child: Builder(builder: _page),
    );
  }

  Widget _page(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visible = [
      for (final e in _entries)
        if ((e.isFolder ||
                (!widget.chooseFolder &&
                    (_filter == null || e.kind == _filter))) &&
            (_query.isEmpty ||
                e.name.toLowerCase().contains(_query.toLowerCase())))
          e,
    ];
    final folders = [
      for (final e in visible)
        if (e.isFolder) e,
    ];
    final files = [
      for (final e in visible)
        if (!e.isFolder) e,
    ];
    final parent = Directory(_folder).parent.path;
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final places = _places(l10n);
    final placeList = [
      for (final (icon, label, path) in places)
        ListTile(
          dense: true,
          leading: Icon(icon),
          title: Text(label),
          selected: _folder == path,
          onTap: () => _open(path),
        ),
    ];
    final grid = _loading
        ? const Center(child: CircularProgressIndicator())
        : visible.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    l10n.browserEmpty,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            : Scrollbar(
                child: CustomScrollView(
                  slivers: [
                    // Folders are compact rows, so the media stays in view.
                    SliverPadding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      sliver: SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 240,
                          mainAxisExtent: 48,
                          mainAxisSpacing: AppSpacing.sm,
                          crossAxisSpacing: AppSpacing.sm,
                        ),
                        itemCount: folders.length,
                        itemBuilder: (context, i) => _FolderTile(
                          entry: folders[i],
                          onOpen: () => _open(folders[i].path),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.sm,
                        0,
                        AppSpacing.sm,
                        AppSpacing.sm,
                      ),
                      sliver: SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 160,
                          mainAxisSpacing: AppSpacing.sm,
                          crossAxisSpacing: AppSpacing.sm,
                          childAspectRatio: 0.82,
                        ),
                        itemCount: files.length,
                        itemBuilder: (context, i) => _FileTile(
                          entry: files[i],
                          order: _picked.indexOf(files[i].path),
                          onTap: () => _toggle(files[i].path),
                        ),
                      ),
                    ),
                  ],
                ),
              );
    final folderMode = widget.chooseFolder;
    final addButton = folderMode
        ? FilledButton.icon(
            onPressed: () => Navigator.of(context).pop([_folder]),
            icon: const Icon(Icons.check),
            label: Text(l10n.browserUseFolder),
          )
        : FilledButton.icon(
            onPressed: _picked.isEmpty
                ? null
                : () => Navigator.of(context).pop(List.of(_picked)),
            icon: const Icon(Icons.add),
            label: Text(l10n.browserAdd(_picked.length)),
          );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.cancelAction,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(folderMode ? l10n.browserFolderTitle : l10n.browserTitle),
        actions: [
          if (wide)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: addButton,
            ),
        ],
      ),
      // On phones the confirm button sits under the thumb.
      bottomNavigationBar: wide || (!folderMode && _picked.isEmpty)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: SizedBox(height: 52, child: addButton),
              ),
            ),
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              SizedBox(
                width: 220,
                child: ListView(children: placeList),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!wide)
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                        children: [
                          for (final (icon, label, path) in places)
                            Padding(
                              padding: const EdgeInsets.only(
                                right: AppSpacing.sm,
                              ),
                              child: ChoiceChip(
                                avatar: Icon(icon, size: 18),
                                label: Text(label),
                                selected: _folder == path,
                                onSelected: (_) => _open(path),
                              ),
                            ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: l10n.browserUp,
                          icon: const Icon(Icons.arrow_upward),
                          onPressed:
                              parent == _folder ? null : () => _open(parent),
                        ),
                        Expanded(
                          child: Text(
                            _folder,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    child: TextField(
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search),
                        hintText: l10n.browserSearch,
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  if (!folderMode)
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        children: [
                          for (final (kind, label) in <(MediaKind?, String)>[
                            (null, l10n.filterAllMedia),
                            (MediaKind.video, l10n.layerKindVideo),
                            (MediaKind.image, l10n.layerKindImage),
                            (MediaKind.audio, l10n.layerKindAudio),
                          ])
                            Padding(
                              padding:
                                  const EdgeInsets.only(right: AppSpacing.sm),
                              child: ChoiceChip(
                                label: Text(label),
                                selected: _filter == kind,
                                onSelected: (_) =>
                                    setState(() => _filter = kind),
                              ),
                            ),
                        ],
                      ),
                    ),
                  Expanded(child: grid),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.entry, required this.onOpen});

  final _Entry entry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppRadii.medium),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        onTap: onOpen,
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.md),
            Icon(Icons.folder, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileTile extends ConsumerWidget {
  const _FileTile({
    required this.entry,
    required this.order,
    required this.onTap,
  });

  final _Entry entry;

  /// Position among the chosen files, or -1.
  final int order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final audio = entry.kind == MediaKind.audio;
    final poster =
        audio ? null : ref.watch(videoPosterProvider(entry.path)).valueOrNull;
    final chosen = order >= 0;
    return Semantics(
      selected: chosen,
      button: true,
      label: entry.name,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        onTap: onTap,
        child: Column(
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  color: audio
                      ? scheme.secondaryContainer
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                  border: Border.all(
                    color: chosen ? scheme.primary : scheme.surface,
                    width: 3,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.medium - 3),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (poster != null)
                        RawImage(image: poster, fit: BoxFit.cover)
                      else
                        Icon(
                          audio
                              ? Icons.graphic_eq
                              : entry.kind == MediaKind.image
                                  ? Icons.image_outlined
                                  : Icons.movie_outlined,
                          size: 40,
                          color: audio
                              ? scheme.onSecondaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                      Positioned(
                        left: AppSpacing.xs,
                        bottom: AppSpacing.xs,
                        child: Icon(
                          switch (entry.kind) {
                            MediaKind.video => Icons.videocam,
                            MediaKind.image => Icons.photo,
                            _ => Icons.music_note,
                          },
                          size: 16,
                          color: scheme.onSurface,
                          shadows: [Shadow(color: scheme.scrim, blurRadius: 4)],
                        ),
                      ),
                      if (chosen)
                        Positioned(
                          right: AppSpacing.xs,
                          top: AppSpacing.xs,
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: scheme.primary,
                            child: Text(
                              '${order + 1}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onPrimary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}
