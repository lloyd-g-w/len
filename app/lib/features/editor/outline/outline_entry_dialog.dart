import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/outline/outline_tree.dart';
import '../../../ui/app_dialogs.dart';
import '../../../ui/app_theme.dart';

/// Title and parent (null = top level) entered in [showOutlineEntryDialog].
typedef OutlineEntryDetails = ({String title, String? parentId});

/// Asks for the title of an outline entry and, when [parents] are given,
/// the entry to nest it under.
Future<OutlineEntryDetails?> showOutlineEntryDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initialTitle = '',
  List<OutlineTreeRow>? parents,
  String? initialParent,
}) => showDialog<OutlineEntryDetails>(
  context: context,
  builder: (_) => _OutlineEntryDialog(
    title: title,
    confirmLabel: confirmLabel,
    initialTitle: initialTitle,
    parents: parents,
    initialParent: initialParent,
  ),
);

class _OutlineEntryDialog extends StatefulWidget {
  const _OutlineEntryDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialTitle,
    required this.parents,
    required this.initialParent,
  });

  final String title;
  final String confirmLabel;
  final String initialTitle;
  final List<OutlineTreeRow>? parents;
  final String? initialParent;

  @override
  State<_OutlineEntryDialog> createState() => _OutlineEntryDialogState();
}

class _OutlineEntryDialogState extends State<_OutlineEntryDialog> {
  late final _title = TextEditingController(text: widget.initialTitle)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initialTitle.length);
  late String? _parent = widget.initialParent;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    Navigator.pop<OutlineEntryDetails>(context, (title: title, parentId: _parent));
  }

  @override
  Widget build(BuildContext context) {
    final parents = widget.parents;
    return AppDialog(
      title: widget.title,
      content: DialogBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('outline-title-field'),
              controller: _title,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title'),
              onSubmitted: (_) => _submit(),
            ),
            if (parents != null && parents.isNotEmpty) ...[
              const SizedBox(height: Gaps.lg),
              DropdownButtonFormField<String?>(
                icon: const Icon(Symbols.expand_more_rounded),
                key: const ValueKey('outline-parent-field'),
                initialValue: _parent,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Nested under'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Top level')),
                  for (final row in parents)
                    DropdownMenuItem(
                      value: row.entry.id,
                      child: Padding(
                        padding: EdgeInsets.only(left: row.depth * 16.0),
                        child: Text(row.entry.title, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                ],
                onChanged: (id) => setState(() => _parent = id),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ListenableBuilder(
          listenable: _title,
          builder: (context, _) => FilledButton(
            onPressed: _title.text.trim().isEmpty ? null : _submit,
            child: Text(widget.confirmLabel),
          ),
        ),
      ],
    );
  }
}
