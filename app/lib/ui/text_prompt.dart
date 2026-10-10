import 'package:flutter/material.dart';

import 'app_dialogs.dart';

/// Asks for a single line of text. Returns the trimmed text, or null if
/// cancelled. [label] names the field (e.g. "Title"); [icon] leads it.
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String confirmLabel = 'OK',
  String? label,
  IconData? icon,
  TextInputType? keyboardType,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextPromptDialog(
      title: title,
      initialValue: initialValue,
      confirmLabel: confirmLabel,
      label: label,
      icon: icon,
      keyboardType: keyboardType,
    ),
  );
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.initialValue,
    required this.confirmLabel,
    this.label,
    this.icon,
    this.keyboardType,
  });

  final String title;
  final String initialValue;
  final String confirmLabel;
  final String? label;
  final IconData? icon;
  final TextInputType? keyboardType;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final _controller = TextEditingController(text: widget.initialValue)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initialValue.length);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: DialogBody(
        child: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: widget.keyboardType,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: widget.icon == null ? null : Icon(widget.icon),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => FilledButton(
            onPressed: _controller.text.trim().isEmpty ? null : _submit,
            child: Text(widget.confirmLabel),
          ),
        ),
      ],
    );
  }
}
