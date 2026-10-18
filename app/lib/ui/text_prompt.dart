import 'package:flutter/material.dart';

import 'app_dialogs.dart';

/// Asks for a single line of text. Returns the trimmed text, or null if
/// cancelled. [label] names the field (e.g. "Title"). An empty answer is
/// only accepted (button and Enter alike) with [allowEmpty], for fields
/// where empty means "no name".
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String confirmLabel = 'OK',
  String? label,
  TextInputType? keyboardType,
  bool allowEmpty = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextPromptDialog(
      title: title,
      initialValue: initialValue,
      confirmLabel: confirmLabel,
      label: label,
      keyboardType: keyboardType,
      allowEmpty: allowEmpty,
    ),
  );
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.initialValue,
    required this.confirmLabel,
    this.label,
    this.keyboardType,
    this.allowEmpty = false,
  });

  final String title;
  final String initialValue;
  final String confirmLabel;
  final String? label;
  final TextInputType? keyboardType;
  final bool allowEmpty;

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

  bool get _canSubmit => widget.allowEmpty || _controller.text.trim().isNotEmpty;

  void _submit() {
    if (_canSubmit) Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: widget.title,
      content: DialogBody(
        child: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: widget.keyboardType,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(labelText: widget.label),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: Text(widget.confirmLabel),
          ),
        ),
      ],
    );
  }
}
