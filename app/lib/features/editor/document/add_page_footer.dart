import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import 'document_controller.dart';
import 'document_layout.dart';

/// "＋ Add page" below the last page of a continuous document, following
/// the page as the document scrolls and zooms (GoodNotes' end-of-document
/// affordance). Held down (or right-clicked), it asks for a template, like
/// "Add page after" in the page menu.
class AddPageFooter extends StatelessWidget {
  const AddPageFooter({
    super.key,
    required this.doc,
    required this.onAdd,
    required this.onAddWithTemplate,
  });

  final DocumentController doc;
  final VoidCallback onAdd;
  final VoidCallback onAddWithTemplate;

  static const double height = 52, gap = 24;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([doc, doc.viewport]),
      builder: (context, _) {
        final page = doc.lastPageOnScreen;
        final size = doc.viewport.size;
        if (doc.flow != PageFlow.continuous || page == null) return const SizedBox.shrink();
        final top = page.bottom + gap;
        if (top > size.height || top + height < 0) return const SizedBox.shrink();
        final width = math.min(math.max(page.width * 0.6, 200.0), 360.0);
        return Stack(
          children: [
            Positioned(
              left: page.center.dx - width / 2,
              top: top,
              width: width,
              height: height,
              child: _AddButton(onAdd: onAdd, onAddWithTemplate: onAddWithTemplate),
            ),
          ],
        );
      },
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onAdd, required this.onAddWithTemplate});

  final VoidCallback onAdd;
  final VoidCallback onAddWithTemplate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A Pencil-edged outline with an Ink +, like the library's New tile.
    return GestureDetector(
      onSecondaryTap: onAddWithTemplate,
      child: OutlinedButton.icon(
        onPressed: onAdd,
        onLongPress: onAddWithTemplate,
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          backgroundColor: Colors.transparent,
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm)),
        ),
        icon: const Icon(Symbols.add_sharp),
        label: const Text('Add page'),
      ),
    );
  }
}
