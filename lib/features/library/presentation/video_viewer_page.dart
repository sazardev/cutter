import 'dart:async';

import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/core/engine/media_engine.dart';
import 'package:cutter/features/editor/domain/editor_result.dart';
import 'package:cutter/features/editor/domain/export_record.dart';
import 'package:cutter/features/editor/domain/project.dart';
import 'package:cutter/features/editor/presentation/editor_page.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/time_format.dart';
import 'package:cutter/features/library/presentation/videos_section.dart';
import 'package:cutter/features/settings/presentation/appearance_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How long the delete button waits for its second tap.
const Duration _confirmWindow = Duration(seconds: 4);

/// One rendered video: played by the engine, with its details and what can
/// be done with it. Deleting needs a second tap on the same button, since a
/// deleted file cannot come back.
class VideoViewerPage extends ConsumerStatefulWidget {
  /// Creates the viewer of [record].
  const VideoViewerPage({required this.record, super.key});

  /// The video shown.
  final ExportRecord record;

  @override
  ConsumerState<VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends ConsumerState<VideoViewerPage> {
  PreviewSession? _session;
  StreamSubscription<PlaybackState>? _states;
  int _position = 0;
  bool _playing = false;
  bool _confirmDelete = false;
  Timer? _confirmTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    final r = widget.record;
    final session = await ref.read(mediaEngineProvider).openPreview();
    if (!mounted) {
      session.dispose();
      return;
    }
    session.setTimeline(
      Timeline(
        width: r.width,
        height: r.height,
        fps: r.fps,
        layers: [
          TimelineLayer(
            kind: EngineMediaKind.video,
            volume: 1,
            muted: false,
            clips: [
              TimelineClip(
                path: r.path,
                kind: EngineMediaKind.video,
                startMs: 0,
                inMs: 0,
                outMs: r.durationMs,
                reversed: false,
                volume: 1,
                brightness: 0,
                contrast: 0,
                saturation: 0,
                x: 0,
                y: 0,
                scale: 1,
                rotation: 0,
                opacity: 1,
                flipX: false,
                fill: false,
                cropLeft: 0,
                cropTop: 0,
                cropRight: 0,
                cropBottom: 0,
                speed: 1,
                fadeInMs: 0,
                fadeOutMs: 0,
                blur: 0,
                vignette: 0,
                grain: 0,
                pixelate: 0,
                sharpen: 0,
                animInMs: 0,
                animOutMs: 0,
              ),
            ],
          ),
        ],
      ),
    );
    _states = session.states.listen((s) {
      if (mounted) {
        setState(() {
          _position = s.positionMs;
          _playing = s.playing;
        });
      }
    });
    setState(() => _session = session);
  }

  @override
  void dispose() {
    _confirmTimer?.cancel();
    unawaited(_states?.cancel());
    _session?.dispose();
    super.dispose();
  }

  void _toggle() {
    final session = _session;
    if (session == null) return;
    if (_playing) {
      session.pause();
    } else {
      if (_position >= widget.record.durationMs) session.seek(0);
      session.play();
    }
    setState(() => _playing = !_playing);
  }

  Future<void> _delete() async {
    if (!_confirmDelete) {
      setState(() => _confirmDelete = true);
      _confirmTimer = Timer(_confirmWindow, () {
        if (mounted) setState(() => _confirmDelete = false);
      });
      return;
    }
    await ref.read(exportLibraryProvider).remove(widget.record.id);
    ref.invalidate(exportRecordsProvider);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _editInNewProject() async {
    final l10n = AppLocalizations.of(context)!;
    final navigator = Navigator.of(context);
    final result = await ref.read(createProjectProvider).call(
          name: l10n.remixProjectName(widget.record.projectName),
        );
    if (result case Ok<Project>(:final value)) {
      ref.invalidate(projectSummariesProvider);
      await navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => EditorPage(
            projectId: value.id,
            initialImport: [widget.record.path],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ref.watch(editorThemeProvider),
      child: Builder(builder: _page),
    );
  }

  /// The page under the dark theme: [context] is inside it, so every text
  /// and colour reads the dark scheme.
  Widget _page(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final r = widget.record;
    final textureId = _session?.textureId;
    final created = DateTime.fromMillisecondsSinceEpoch(r.createdAtMs);
    final details = [
      '${r.width} × ${r.height}',
      l10n.exportFpsValue(r.fps),
      formatTimecode(r.durationMs, tenths: true),
      formatBytes(r.sizeBytes),
      MaterialLocalizations.of(context).formatMediumDate(created),
    ].join(' · ');
    return Scaffold(
      appBar: AppBar(title: Text(r.projectName)),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: r.width / r.height,
                    child: GestureDetector(
                      onTap: _toggle,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadii.small),
                        child: ColoredBox(
                          color: Theme.of(context).colorScheme.scrim,
                          child: textureId == null
                              ? const SizedBox.expand()
                              : Texture(textureId: textureId),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Slider(
              value: _position.clamp(0, r.durationMs).toDouble(),
              max: r.durationMs.toDouble().clamp(1, double.infinity),
              onChangeStart: (_) => _session?.pause(),
              onChanged: (v) {
                _session?.seek(v.round());
                setState(() => _position = v.round());
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  formatTimecode(_position, tenths: true),
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(width: AppSpacing.md),
                IconButton.filledTonal(
                  tooltip: _playing ? l10n.pauseAction : l10n.playAction,
                  iconSize: 32,
                  icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                  onPressed: _toggle,
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  formatTimecode(r.durationMs, tenths: true),
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(details, style: theme.textTheme.bodyMedium),
                  if (r.inGallery)
                    Text(
                      l10n.inGalleryNote,
                      style: theme.textTheme.bodySmall,
                    ),
                  SelectableText(
                    r.path,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _editInNewProject,
                        icon: const Icon(Icons.movie_edit),
                        label: Text(l10n.remixAction),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => Clipboard.setData(
                          ClipboardData(text: r.path),
                        ),
                        icon: const Icon(Icons.copy),
                        label: Text(l10n.copyPathAction),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
                        onPressed: _delete,
                        icon: const Icon(Icons.delete_outline),
                        label: Text(
                          _confirmDelete
                              ? l10n.deleteVideoConfirm
                              : l10n.deleteVideoAction,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
