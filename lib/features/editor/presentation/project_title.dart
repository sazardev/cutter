import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/features/editor/domain/rename_project.dart';
import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The project name in the top bar. A tap turns it into a field in place
/// (no dialog); Enter or leaving the field keeps the new name, Esc keeps the
/// old one, and a blank name is ignored.
class ProjectTitle extends ConsumerStatefulWidget {
  /// Creates the title showing [name].
  const ProjectTitle({required this.name, super.key});

  /// The current name of the project.
  final String name;

  @override
  ConsumerState<ProjectTitle> createState() => _ProjectTitleState();
}

class _ProjectTitleState extends ConsumerState<ProjectTitle> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commit();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _start() {
    _text.text = widget.name;
    _text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.name.length,
    );
    setState(() => _editing = true);
    _focus.requestFocus();
  }

  void _cancel() {
    if (!_editing) return;
    setState(() => _editing = false);
    _focus.unfocus();
  }

  Future<void> _commit() async {
    if (!_editing) return;
    final name = _text.text.trim();
    setState(() => _editing = false);
    _focus.unfocus();
    if (name.isEmpty || name == widget.name) return;
    await ref.read(editorControllerProvider.notifier).rename(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    if (_editing) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _cancel,
          },
          child: TextField(
            controller: _text,
            focusNode: _focus,
            autofocus: true,
            maxLength: maxProjectNameLength,
            textInputAction: TextInputAction.done,
            style: theme.textTheme.titleLarge,
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              hintText: l10n.projectNameLabel,
            ),
            onSubmitted: (_) => _commit(),
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: l10n.renameProjectLabel(widget.name),
      excludeSemantics: true,
      child: Tooltip(
        message: l10n.renameProjectTooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.small),
          onTap: _start,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xs,
            ),
            child: Text(widget.name, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    );
  }
}
