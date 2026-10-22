import 'dart:io';

import 'package:cutter/features/editor/domain/import_media.dart';
import 'package:cutter/features/editor/domain/media_asset.dart';
import 'package:cutter/features/editor/domain/media_bank.dart';
import 'package:cutter/features/editor/presentation/editor_controller.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/import_report_dialog.dart';
import 'package:cutter/features/editor/presentation/media/media_browser_page.dart';
import 'package:cutter/features/editor/presentation/media/media_formats.dart';
import 'package:cutter/features/editor/presentation/playback_controller.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Picks media files, optionally of one kind; null when cancelled. Tests
/// replace it.
typedef MediaPicker = Future<List<String>?> Function(
  BuildContext context,
  MediaKind? filter,
);

/// Whether the desktop has no file portal; learnt once, so the in-app
/// browser opens straight away afterwards.
bool _noPortal = false;

/// The extensions offered for [filter], or all media.
List<String> _extensions(MediaKind? filter) => switch (filter) {
      MediaKind.video => videoExtensions.toList(),
      MediaKind.image => imageExtensions.toList(),
      MediaKind.audio => audioExtensions.toList(),
      MediaKind.text => const [],
      null => mediaExtensions.toList(),
    };

/// The system picker, already filtered to media (on Android the document
/// picker, on Linux the portal's dialog); on a desktop without a portal the
/// in-app media browser.
final mediaPickerProvider = Provider<MediaPicker>(
  (ref) => (context, filter) async {
    final mobile = Platform.isAndroid || Platform.isIOS;
    if (mobile || !_noPortal) {
      try {
        final files = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: _extensions(filter),
        );
        return [
          for (final file in files)
            if (file.path != null) file.path!,
        ];
      } on Object {
        if (mobile) rethrow;
        _noPortal = true;
      }
    }
    if (!context.mounted) return null;
    return Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => MediaBrowserPage(initialFilter: filter),
      ),
    );
  },
);

/// Picks media and imports it: into the bank always, and onto the timeline
/// when [toTimeline] is set (where each kind belongs, or as an overlay).
Future<void> pickAndImport(
  BuildContext context,
  WidgetRef ref, {
  bool toTimeline = true,
  ImportPlacement placement = ImportPlacement.append,
  MediaKind? filter,
}) async {
  final paths = await ref.read(mediaPickerProvider)(context, filter);
  if (paths == null || paths.isEmpty || !context.mounted) return;
  await importPaths(
    context,
    ref,
    paths,
    toTimeline: toTimeline,
    placement: placement,
  );
}

/// Imports the files at [paths]. The result shows on the timeline or in the
/// bank; files that were left out, and warnings about big ones, are listed
/// in a report so nothing is dropped silently. [atMs] places sound at that
/// time instead of the playhead.
Future<ImportOutcome> importPaths(
  BuildContext context,
  WidgetRef ref,
  List<String> paths, {
  bool toTimeline = true,
  ImportPlacement placement = ImportPlacement.append,
  int? atMs,
}) async {
  final playhead = atMs ?? ref.read(playbackControllerProvider).positionMs;
  final outcome = await ref.read(editorControllerProvider.notifier).importFiles(
        paths,
        atMs: playhead,
        placement: placement,
        toTimeline: toTimeline,
      );
  if (context.mounted) await showImportReport(context, outcome);
  return outcome;
}

/// Places bank [items] on the timeline.
Future<void> placeFromBank(
  BuildContext context,
  WidgetRef ref,
  List<MediaItem> items, {
  ImportPlacement placement = ImportPlacement.append,
}) async {
  await ref.read(editorControllerProvider.notifier).placeFromBank(
        items,
        atMs: ref.read(playbackControllerProvider).positionMs,
        placement: placement,
      );
}
