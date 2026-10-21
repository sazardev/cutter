import 'dart:async';
import 'dart:io';

import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/core/engine/media_engine.dart';
import 'package:cutter/features/editor/data/engine_timeline.dart';
import 'package:cutter/features/editor/domain/export_preset.dart';
import 'package:cutter/features/editor/domain/export_record.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/missing_media.dart';
import 'package:cutter/features/editor/presentation/project_settings.dart';
import 'package:cutter/features/editor/presentation/share_video.dart';
import 'package:cutter/features/editor/presentation/tools/share_block.dart';
import 'package:cutter/features/settings/presentation/export_preferences_providers.dart';
import 'package:cutter/features/settings/presentation/share_preferences_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

/// The folder finished videos are written to: the one chosen in Settings
/// when it can be written; otherwise `~/Videos/Cutter` on desktop, or on
/// Android the app's Movies folder, from where they are copied into the
/// gallery.
final exportDirectoryProvider = FutureProvider<Directory>((ref) async {
  final chosen = ref.watch(exportPreferencesProvider).directory;
  if (chosen != null) {
    final custom = Directory(chosen);
    if (await isWritableDirectory(custom)) return custom;
  }
  Directory base;
  if (Platform.isAndroid) {
    final movies =
        await getExternalStorageDirectories(type: StorageDirectory.movies);
    base = (movies != null && movies.isNotEmpty)
        ? movies.first
        : await getApplicationDocumentsDirectory();
  } else {
    final home = Platform.environment['HOME'];
    base = home != null
        ? Directory('$home${Platform.pathSeparator}Videos')
        : (await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory());
  }
  final dir = Directory('${base.path}${Platform.pathSeparator}Cutter');
  await dir.create(recursive: true);
  return dir;
});

/// Copies a finished video into the device gallery; tests replace it.
typedef GallerySaver = Future<bool> Function(String path);

/// The system gallery on Android, nothing elsewhere (the file already is in
/// the user's Videos folder).
final gallerySaverProvider = Provider<GallerySaver>(
  (ref) => (path) async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    await Gal.putVideo(path, album: 'Cutter');
    return true;
  },
);

/// Where an export is.
enum ExportPhase {
  /// Settings are being chosen.
  idle,

  /// The engine is rendering.
  running,

  /// The file is ready.
  done,

  /// The engine reported an error.
  failed,
}

/// What the export panel and the progress badge show.
class ExportUi {
  /// Creates the export state.
  const ExportUi({
    this.phase = ExportPhase.idle,
    this.progress = 0,
    this.path,
    this.inGallery = false,
    this.message,
  });

  /// Where the export is.
  final ExportPhase phase;

  /// Fraction rendered, 0 to 1.
  final double progress;

  /// The file written, once known.
  final String? path;

  /// Whether the file was copied into the device gallery.
  final bool inGallery;

  /// The engine's error, when it failed.
  final String? message;
}

/// Runs one export at a time for the open project. It lives as long as the
/// editor, so closing the panel does not stop a render.
class ExportController extends AutoDisposeNotifier<ExportUi> {
  ExportTask? _task;
  StreamSubscription<ExportEvent>? _events;

  @override
  ExportUi build() {
    ref.onDispose(() {
      _task?.cancel();
      unawaited(_events?.cancel());
    });
    return const ExportUi();
  }

  /// Renders [project] for [platform] at [quality] and [fps], then files
  /// the video in the library (and the gallery on phones).
  Future<void> start(
    Project project,
    ExportPlatform platform,
    ExportQuality quality,
    int fps,
  ) async {
    if (state.phase == ExportPhase.running) return;
    final own = await projectExportDirectory(ref, project.id);
    final shared = await ref.read(exportDirectoryProvider.future);
    final dir = own ?? shared;
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp('[^0-9]'), '')
        .substring(0, 14);
    final safeName = project.name.replaceAll(RegExp(r'[^\w\- ]'), '_');
    final path = '${dir.path}${Platform.pathSeparator}${safeName}_$stamp.mp4';
    final plan = ExportPlan.of(project.canvas, platform, quality, fps);
    final timeline = engineTimelineOf(
      project,
      missingSources: ref.read(missingSourcesProvider).valueOrNull ?? const {},
    );
    final task = ref.read(mediaEngineProvider).export(
          Timeline(
            width: plan.width,
            height: plan.height,
            fps: plan.fps,
            layers: timeline.layers,
          ),
          ExportSettings(
            width: plan.width,
            height: plan.height,
            fps: plan.fps,
            videoBitrate: plan.videoBitrate,
            audioBitrate: plan.audioBitrate,
            encoderPreset: plan.encoderPreset,
          ),
          path,
        );
    _task = task;
    state = ExportUi(phase: ExportPhase.running, path: path);
    await _events?.cancel();
    _events = task.events.listen((event) async {
      switch (event.stage) {
        case ExportStage.running:
          state = ExportUi(
            phase: ExportPhase.running,
            progress: event.progress,
            path: path,
          );
        case ExportStage.done:
          var inGallery = false;
          try {
            inGallery = await ref.read(gallerySaverProvider)(path);
          } on Object {
            inGallery = false;
          }
          final file = File(path);
          await ref.read(exportLibraryProvider).add(
                ExportRecord(
                  id: ref.read(idGeneratorProvider).next(),
                  path: path,
                  projectId: project.id,
                  projectName: project.name,
                  width: plan.width,
                  height: plan.height,
                  fps: plan.fps,
                  durationMs: project.durationMs,
                  sizeBytes: file.existsSync() ? file.lengthSync() : 0,
                  createdAtMs: DateTime.now().millisecondsSinceEpoch,
                  preset: '${platform.name}/${quality.name}',
                  inGallery: inGallery,
                ),
              );
          ref.invalidate(exportRecordsProvider);
          state = ExportUi(
            phase: ExportPhase.done,
            progress: 1,
            path: path,
            inGallery: inGallery,
          );
          // When the user asked for it, the share sheet opens on its own.
          final share = ref.read(sharePreferencesProvider);
          if (share.showAfterExport &&
              share.openSheetAutomatically &&
              ref.read(shareSupportedProvider)) {
            try {
              await ref.read(videoSharerProvider)(path, project.name);
            } on Object {
              // No share target: the buttons in the panel remain.
            }
          }
        case ExportStage.failed:
          state = ExportUi(phase: ExportPhase.failed, message: event.message);
        case ExportStage.cancelled:
          state = const ExportUi();
      }
    });
  }

  /// Stops the running export; the partial file is removed.
  void cancel() => _task?.cancel();

  /// Back to the settings after a finished or failed export.
  void reset() {
    if (state.phase != ExportPhase.running) state = const ExportUi();
  }
}

/// The export of the open editor.
final exportControllerProvider =
    AutoDisposeNotifierProvider<ExportController, ExportUi>(
  ExportController.new,
);

/// Resolution, frame rate, progress and result of the export, in place.
class ExportPanel extends ConsumerStatefulWidget {
  /// Creates the panel.
  const ExportPanel({super.key});

  @override
  ConsumerState<ExportPanel> createState() => _ExportPanelState();
}

class _ExportPanelState extends ConsumerState<ExportPanel> {
  ExportPlatform _platform = ExportPlatform.project;
  ExportQuality _quality = ExportQuality.standard;
  int? _fps;

  String _platformLabel(AppLocalizations l10n, ExportPlatform p) => switch (p) {
        ExportPlatform.project => l10n.platformProject,
        ExportPlatform.vertical => l10n.platformVertical,
        ExportPlatform.widescreen => l10n.platformWidescreen,
        ExportPlatform.feed => l10n.platformFeed,
        ExportPlatform.messaging => l10n.platformMessaging,
      };

  String _qualityLabel(AppLocalizations l10n, ExportQuality q) => switch (q) {
        ExportQuality.draft => l10n.qualityDraft,
        ExportQuality.standard => l10n.qualityStandard,
        ExportQuality.high => l10n.qualityHigh,
        ExportQuality.ultra => l10n.qualityUltra,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final project = ref.watch(editorControllerProvider).valueOrNull?.project;
    final export = ref.watch(exportControllerProvider);
    final controller = ref.read(exportControllerProvider.notifier);
    if (project == null) return const SizedBox.shrink();
    final fps = _fps ?? project.canvas.fps;
    final plan = ExportPlan.of(project.canvas, _platform, _quality, fps);
    final hasMissing =
        ref.watch(missingSourcesProvider).valueOrNull?.isNotEmpty ?? false;
    final megabytes = plan.estimatedBytes(project.durationMs) / (1024 * 1024);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: switch (export.phase) {
        ExportPhase.idle => [
            Text(l10n.exportPlatformLabel, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final p in ExportPlatform.values)
                  ChoiceChip(
                    label: Text(_platformLabel(l10n, p)),
                    selected: _platform == p,
                    onSelected: (_) => setState(() => _platform = p),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(l10n.exportQualityLabel, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            SegmentedButton<ExportQuality>(
              showSelectedIcon: false,
              segments: [
                for (final q in ExportQuality.values)
                  ButtonSegment(value: q, label: Text(_qualityLabel(l10n, q))),
              ],
              selected: {_quality},
              onSelectionChanged: (s) => setState(() => _quality = s.single),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(l10n.exportFpsLabel, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            SegmentedButton<int>(
              segments: [
                for (final value in const [24, 30, 60])
                  ButtonSegment(
                    value: value,
                    label: Text(l10n.exportFpsValue(value)),
                  ),
              ],
              selected: {fps},
              emptySelectionAllowed: true,
              onSelectionChanged: (s) {
                if (s.isNotEmpty) setState(() => _fps = s.single);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.exportPlanSummary(
                plan.width,
                plan.height,
                plan.fps,
                megabytes.toStringAsFixed(megabytes < 10 ? 1 : 0),
              ),
              style: theme.textTheme.bodyMedium,
            ),
            if (plan.reframed) Text(l10n.exportReframedNote, style: muted),
            const SizedBox(height: AppSpacing.md),
            if (hasMissing)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(l10n.exportMissingMedia, style: muted),
              ),
            FilledButton.icon(
              onPressed: project.durationMs == 0 || hasMissing
                  ? null
                  : () => controller.start(project, _platform, _quality, fps),
              icon: const Icon(Icons.file_upload_outlined),
              label: Text(l10n.exportAction),
            ),
          ],
        ExportPhase.running => [
            Text(
              l10n.exportProgress((export.progress * 100).round()),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(value: export.progress),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.exportKeepEditing,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: controller.cancel,
                child: Text(l10n.cancelAction),
              ),
            ),
          ],
        ExportPhase.done => [
            Row(
              children: [
                Icon(Icons.check_circle, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    export.inGallery ? l10n.exportInGallery : l10n.exportDone,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            SelectableText(
              export.path ?? '',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ShareBlock(path: export.path ?? '', title: project.name),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: controller.reset,
                child: Text(l10n.exportAgainAction),
              ),
            ),
          ],
        ExportPhase.failed => [
            Row(
              children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.exportFailed,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
            if (export.message != null)
              SelectableText(
                export.message!,
                style: theme.textTheme.bodySmall,
              ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: controller.reset,
                child: Text(l10n.retryAction),
              ),
            ),
          ],
      },
    );
  }
}
