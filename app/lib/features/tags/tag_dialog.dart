import 'package:flutter/material.dart';

import '../../data/tag_repository.dart';
import '../../ui/app_dialogs.dart';
import '../../ui/app_theme.dart';
import '../../ui/color_dot.dart';
import '../../ui/even_grid.dart';
import 'tag_widgets.dart';

/// Name and colour of a tag, as entered in [showTagDialog].
typedef TagDetails = ({String name, int color});

/// The colour a new tag gets: the first cover colour no tag uses yet.
int nextTagColor(Iterable<int> used) {
  final taken = used.toSet();
  return Palette.covers.firstWhere((c) => !taken.contains(c), orElse: () => Palette.covers.first);
}

/// Creates or edits a tag's name and colour.
Future<TagDetails?> showTagDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initialName = '',
  required int initialColor,
}) => showDialog<TagDetails>(
  context: context,
  builder: (_) => _TagDialog(
    title: title,
    confirmLabel: confirmLabel,
    initialName: initialName,
    initialColor: initialColor,
  ),
);

class _TagDialog extends StatefulWidget {
  const _TagDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialName,
    required this.initialColor,
  });

  final String title;
  final String confirmLabel;
  final String initialName;
  final int initialColor;

  @override
  State<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<_TagDialog> {
  late final _name = TextEditingController(text: widget.initialName)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initialName.length);
  late int _color = widget.initialColor;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop<TagDetails>(context, (name: name, color: _color));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppDialog(
      scrollable: true,
      leading: Center(child: TagDot(_color, size: 28)),
      title: widget.title,
      content: DialogBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListenableBuilder(
              listenable: _name,
              builder: (context, _) => TextField(
                controller: _name,
                autofocus: true,
                maxLength: TagRepository.maxNameLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Name', counterText: ''),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(height: Gaps.xl),
            Text('Colour', style: theme.textTheme.titleSmall),
            const SizedBox(height: Gaps.sm),
            EvenGrid(
              itemExtent: 40,
              minItemExtent: 32,
              children: [
                for (var i = 0; i < Palette.covers.length; i++)
                  ColorDot(
                    color: Palette.covers[i],
                    size: 40,
                    tooltip: Palette.coverNames[i],
                    selected: Palette.covers[i] == _color,
                    onTap: () => setState(() => _color = Palette.covers[i]),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ListenableBuilder(
          listenable: _name,
          builder: (context, _) => FilledButton(
            onPressed: _name.text.trim().isEmpty ? null : _submit,
            child: Text(widget.confirmLabel),
          ),
        ),
      ],
    );
  }
}
