import 'dart:async';
import 'dart:io';

import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/domain/rename_project.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/editor/presentation/layout/editor_layout.dart';
import 'package:cutter/features/editor/presentation/media/media_browser_page.dart';
import 'package:cutter/features/editor/presentation/project_settings.dart';
import 'package:cutter/features/editor/presentation/time_format.dart';
import 'package:cutter/features/editor/presentation/tools/editor_tool.dart';
import 'package:cutter/features/settings/presentation/export_preferences_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How long "Saved" shows on the save button after a restore point.
const Duration _savedFlash = Duration(seconds: 2);

/// Everything about the project itself, in place: its name, a restore point
/// on demand, where its videos are saved, its format, and deleting it. A
/// delete asks first, in the panel, and cannot be undone.
class ProjectSettingsPanel extends ConsumerStatefulWidget {
  /// Creates the panel.
  const ProjectSettingsPanel({super.key});

  @override
  ConsumerState<ProjectSettingsPanel> createState() =>
      _ProjectSettingsPanelState();
}

class _ProjectSettingsPanelState extends ConsumerState<ProjectSettingsPanel> {
  final TextEditingController _name = TextEditingController();
  String _shownName = '';
  bool _justSaved = false;
  bool _confirmDelete = false;
  Timer? _flash;

  @override
  void dispose() {
    _flash?.cancel();
    _name.dispose();
    super.dispose();
  }

  Future<void> _rename() async {
    final name = _name.text.trim();
    if (name.isEmpty || name == _shownName) return;
    await ref.read(editorControllerProvider.notifier).rename(name);
  }

  Future<void> _savePoint(String name) async {
    final version =
        await ref.read(editorControllerProvider.notifier).saveVersion(name);
    if (version == null || !mounted) return;
    setState(() => _justSaved = true);
    _flash?.cancel();
    _flash = Timer(_savedFlash, () {
      if (mounted) setState(() => _justSaved = false);
    });
  }

  /// A folder from the system picker, or from the in-app browser when the
  /// system has none (a desktop without a portal).
  Future<String?> _pickFolder() async {
    try {
      return await ref.read(directoryPickerProvider)();
    } on Object {
      if (!mounted) return null;
      final picked = await Navigator.of(context).push<List<String>>(
        MaterialPageRoute(
          builder: (_) => const MediaBrowserPage(chooseFolder: true),
        ),
      );
      return picked == null || picked.isEmpty ? null : picked.first;
    }
  }

  Future<void> _chooseFolder(String projectId) async {
    final path = await _pickFolder();
    if (path == null) return;
    // A folder that cannot be written to is not taken.
    if (!await isWritableDirectory(Directory(path))) return;
    await _storeFolder(projectId, path);
  }

  Future<void> _storeFolder(String projectId, String path) async {
    await ref
        .read(settingsStoreProvider)
        .write(projectExportDirKey(projectId), path);
    ref.invalidate(projectExportDirProvider(projectId));
  }

  Future<void> _delete() async {
    final deleted =
        await ref.read(editorControllerProvider.notifier).deleteProject();
    if (!deleted || !mounted) return;
    ref.read(activeToolProvider.notifier).state = null;
    await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final editor = ref.watch(editorControllerProvider).valueOrNull;
    if (editor == null) return const SizedBox.shrink();
    final project = editor.project;
    if (_shownName != project.name) {
      _shownName = project.name;
      _name.text = project.name;
    }
    final folder = ref.watch(projectExportDirProvider(project.id)).valueOrNull;
    final versions =
        ref.watch(projectVersionsProvider(project.id)).valueOrNull ?? const [];
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.md,
            bottom: AppSpacing.xs,
          ),
          child: Text(text, style: theme.textTheme.titleSmall),
        );
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final summary = l10n.projectSummary(
      project.layers.length,
      formatTimecode(project.durationMs, tenths: true),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _name,
          maxLength: maxProjectNameLength,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            labelText: l10n.projectNameLabel,
            suffixIcon: IconButton(
              tooltip: l10n.renameAction,
              icon: const Icon(Icons.check),
              onPressed: _rename,
            ),
          ),
          onSubmitted: (_) => _rename(),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${project.canvas.width} × ${project.canvas.height} · '
          '${l10n.exportFpsValue(project.canvas.fps)} · '
          '$summary',
          style: muted,
        ),
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                ref.read(activeToolProvider.notifier).state = EditorTool.canvas,
            icon: const Icon(Icons.aspect_ratio),
            label: Text(l10n.changeFormatAction),
          ),
        ),
        heading(l10n.projectSaveTitle),
        Text(l10n.projectSaveBody(versions.length), style: muted),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: () =>
                _savePoint(l10n.defaultVersionName(versions.length + 1)),
            icon: Icon(_justSaved ? Icons.check : Icons.save_outlined),
            label: Text(
              _justSaved ? l10n.restorePointSaved : l10n.savePointNowAction,
            ),
          ),
        ),
        heading(l10n.projectFolderTitle),
        Text(folder ?? l10n.projectFolderDefault, style: muted),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: () => _chooseFolder(project.id),
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(l10n.projectFolderChoose),
            ),
            if (folder != null)
              TextButton(
                onPressed: () => _storeFolder(project.id, ''),
                child: Text(l10n.projectFolderUseDefault),
              ),
          ],
        ),
        heading(l10n.deleteProjectTitle),
        if (!_confirmDelete)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
              onPressed: () => setState(() => _confirmDelete = true),
              icon: const Icon(Icons.delete_outline),
              label: Text(l10n.deleteProjectAction),
            ),
          )
        else
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(AppRadii.medium),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.deleteProjectAsk(project.name),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.error,
                          foregroundColor: scheme.onError,
                        ),
                        onPressed: _delete,
                        child: Text(l10n.deleteProjectConfirm),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _confirmDelete = false),
                        child: Text(l10n.keepProjectAction),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
