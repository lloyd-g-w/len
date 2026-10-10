import 'package:flutter/material.dart';

/// Asks for a single line of text. Returns the trimmed text, or null if
/// cancelled.
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String confirmLabel = 'OK',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) =>
        _TextPromptDialog(title: title, initialValue: initialValue, confirmLabel: confirmLabel),
  );
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.initialValue,
    required this.confirmLabel,
  });

  final String title;
  final String initialValue;
  final String confirmLabel;

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
      content: TextField(controller: _controller, autofocus: true, onSubmitted: (_) => _submit()),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
