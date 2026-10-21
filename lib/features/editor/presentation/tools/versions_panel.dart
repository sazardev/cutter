import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/domain/project_version.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/time_format.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Saves the project as a named restore point and lists them all, the
/// automatic ones too. The project itself is stored on every edit; restoring
/// a version first saves the current state as a point of its own and can be
/// undone, so it acts at once instead of asking.
class VersionsPanel extends ConsumerStatefulWidget {
  /// Creates the panel.
  const VersionsPanel({super.key});

  @override
  ConsumerState<VersionsPanel> createState() => _VersionsPanelState();
}

String _describe(BuildContext context, ProjectVersion version) {
  final at = DateTime.fromMillisecondsSinceEpoch(version.createdAtMs);
  final date = MaterialLocalizations.of(context).formatShortDate(at);
  final time = TimeOfDay.fromDateTime(at).format(context);
  return '$date · $time · ${formatTimecode(version.durationMs)}';
}

class _VersionsPanelState extends ConsumerState<VersionsPanel> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save(String fallback) async {
    final name = _name.text.trim().isEmpty ? fallback : _name.text;
    final version =
        await ref.read(editorControllerProvider.notifier).saveVersion(name);
    if (version == null) return;
    _name.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final editor = ref.watch(editorControllerProvider).valueOrNull;
    if (editor == null) return const SizedBox.shrink();
    final versions =
        ref.watch(projectVersionsProvider(editor.project.id)).valueOrNull ??
            const [];
    final fallback = l10n.defaultVersionName(versions.length + 1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.cloud_done_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                l10n.statusSavedBody,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.versionsIntro,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _name,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: fallback,
                  labelText: l10n.versionNameLabel,
                ),
                onSubmitted: (_) => _save(fallback),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton.icon(
              onPressed: () => _save(fallback),
              icon: const Icon(Icons.save_outlined),
              label: Text(l10n.saveVersionAction),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (versions.isEmpty)
          Text(
            l10n.noVersionsYet,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final version in versions)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.bookmark_outline),
              title: Text(version.name),
              subtitle: Text(_describe(context, version)),
              trailing: TextButton(
                onPressed: () => ref
                    .read(editorControllerProvider.notifier)
                    .restoreVersion(version.id),
                child: Text(l10n.restoreAction),
              ),
            ),
      ],
    );
  }
}
