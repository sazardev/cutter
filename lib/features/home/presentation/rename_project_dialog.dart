import 'package:cutter/features/editor/domain/rename_project.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Asks for a new name for a project; pops the trimmed name, or null when
/// cancelled. An empty name keeps the dialog open with a message.
class RenameProjectDialog extends StatefulWidget {
  /// Creates the dialog, starting from [currentName].
  const RenameProjectDialog({required this.currentName, super.key});

  /// The name the field starts with.
  final String currentName;

  @override
  State<RenameProjectDialog> createState() => _RenameProjectDialogState();
}

class _RenameProjectDialogState extends State<RenameProjectDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.currentName);
  bool _missing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _missing = true);
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.homeRenameTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: maxProjectNameLength,
        textInputAction: TextInputAction.done,
        onChanged: (_) {
          if (_missing) setState(() => _missing = false);
        },
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: l10n.projectNameLabel,
          errorText: _missing ? l10n.newProjectNameRequired : null,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.renameAction)),
      ],
    );
  }
}
