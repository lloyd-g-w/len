import 'package:flutter/material.dart';

import '../../domain/stickers/sticker.dart';
import '../../ink/images/element_images.dart';
import '../../ui/app_dialogs.dart';
import '../../ui/app_theme.dart';
import 'sticker_preview.dart';

/// Name and category entered in [showSaveStickerDialog].
typedef StickerDetails = ({String name, String category});

/// Asks for the name and category of a sticker made from [content];
/// [categories] are offered as suggestions.
Future<StickerDetails?> showSaveStickerDialog(
  BuildContext context, {
  required StickerContent content,
  required List<String> categories,
  ElementImages? images,
}) => showDialog<StickerDetails>(
  context: context,
  builder: (_) => _SaveStickerDialog(content: content, categories: categories, images: images),
);

class _SaveStickerDialog extends StatefulWidget {
  const _SaveStickerDialog({required this.content, required this.categories, this.images});

  final StickerContent content;
  final List<String> categories;
  final ElementImages? images;

  @override
  State<_SaveStickerDialog> createState() => _SaveStickerDialogState();
}

class _SaveStickerDialogState extends State<_SaveStickerDialog> {
  final _name = TextEditingController(text: 'Sticker');
  late final _category = TextEditingController(text: widget.categories.first);

  @override
  void initState() {
    super.initState();
    _name.selection = TextSelection(baseOffset: 0, extentOffset: _name.text.length);
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim(), category = _category.text.trim();
    if (name.isEmpty || category.isEmpty) return;
    Navigator.pop<StickerDetails>(context, (name: name, category: category));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppDialog(
      scrollable: true,
      leading: Center(
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: Palette.paper,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: StickerPreview(widget.content, images: widget.images),
        ),
      ),
      title: 'Save as sticker',
      content: DialogBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('sticker-name-field'),
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: Gaps.lg),
            TextField(
              key: const ValueKey('sticker-category-field'),
              controller: _category,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Category'),
              onSubmitted: (_) => _submit(),
            ),
            if (widget.categories.length > 1) ...[
              const SizedBox(height: Gaps.sm),
              Wrap(
                spacing: Gaps.xs,
                runSpacing: Gaps.xs,
                children: [
                  for (final c in widget.categories)
                    ActionChip(
                      label: Text(c),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _category.text = c),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
