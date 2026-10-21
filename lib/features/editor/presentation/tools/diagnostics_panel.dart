import 'dart:async';

import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/core/engine/media_engine.dart';
import 'package:cutter/features/editor/presentation/edit_log.dart';
import 'package:cutter/features/editor/presentation/timeline/media_previews.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const Duration _refresh = Duration(seconds: 1);
const int _shownLines = 40;

/// How the engine is doing, refreshed every second: frame timings, late
/// frames, open decoders, cache memory, and the latest engine and edit logs,
/// which can be copied into a bug report.
class DiagnosticsPanel extends ConsumerStatefulWidget {
  /// Creates the panel.
  const DiagnosticsPanel({super.key});

  @override
  ConsumerState<DiagnosticsPanel> createState() => _DiagnosticsPanelState();
}

class _DiagnosticsPanelState extends ConsumerState<DiagnosticsPanel> {
  Timer? _timer;
  EngineDiagnostics? _stats;

  @override
  void initState() {
    super.initState();
    _read();
    _timer = Timer.periodic(_refresh, (_) => _read());
  }

  void _read() {
    try {
      final stats = ref.read(mediaEngineProvider).diagnostics();
      if (mounted) setState(() => _stats = stats);
    } on Object {
      // A missing engine leaves the last numbers on screen.
    }
  }

  static String _megabytes(BigInt? bytes) {
    if (bytes == null) return '– MB';
    return '${(bytes.toInt() / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final stats = _stats;
    final edits = ref.watch(editLogProvider).entries;
    final thumbs = ref.watch(thumbnailStoreProvider).count;
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    final lines = [
      ...?stats?.log,
      for (final entry in edits) 'edit $entry',
    ];
    final shown = lines.length > _shownLines
        ? lines.sublist(lines.length - _shownLines)
        : lines;
    Widget metric(String label, String value) => Padding(
          padding: const EdgeInsets.only(right: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: theme.textTheme.titleMedium),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          runSpacing: AppSpacing.sm,
          children: [
            metric(
              l10n.diagRenderAvg,
              '${stats?.avgRenderMs.toStringAsFixed(1) ?? '–'} ms',
            ),
            metric(
              l10n.diagRenderMax,
              '${stats?.maxRenderMs.toStringAsFixed(1) ?? '–'} ms',
            ),
            metric(l10n.diagLateFrames, '${stats?.lateFrames ?? '–'}'),
            metric(
              l10n.diagDecoders,
              '${stats?.openVideoDecoders ?? '–'} + '
              '${stats?.openAudioDecoders ?? '–'}',
            ),
            metric(l10n.diagCache, _megabytes(stats?.cacheBytes)),
            metric(l10n.diagThumbnails, '$thumbs'),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(l10n.diagLog, style: theme.textTheme.titleSmall),
            ),
            TextButton.icon(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: lines.join('\n'))),
              icon: const Icon(Icons.copy, size: 18),
              label: Text(l10n.copyAction),
            ),
          ],
        ),
        Container(
          constraints: const BoxConstraints(maxHeight: 220),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadii.small),
          ),
          child: SingleChildScrollView(
            reverse: true,
            child: SelectableText(shown.join('\n'), style: mono),
          ),
        ),
      ],
    );
  }
}
