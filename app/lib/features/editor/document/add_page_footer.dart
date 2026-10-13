import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import 'document_controller.dart';
import 'document_layout.dart';

/// "＋ Add page" below the last page of a continuous document, following
/// the page as the document scrolls and zooms (GoodNotes' end-of-document
/// affordance).
class AddPageFooter extends StatelessWidget {
  const AddPageFooter({super.key, required this.doc, required this.onAdd});

  final DocumentController doc;
  final VoidCallback onAdd;

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
              child: _AddButton(onAdd: onAdd),
            ),
          ],
        );
      },
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: onAdd,
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        backgroundColor: scheme.surface.withValues(alpha: 0.6),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.6)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm)),
      ),
      icon: const Icon(Symbols.add_sharp),
      label: const Text('Add page'),
    );
  }
}
