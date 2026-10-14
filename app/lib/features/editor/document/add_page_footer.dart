import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app_services.dart';
import '../../../ui/app_theme.dart';
import 'document_controller.dart';
import 'document_layout.dart';

/// "＋ Add page" below the last page of a continuous document, following
/// the page as the document scrolls and zooms (GoodNotes' end-of-document
/// affordance). Held down (or right-clicked), it asks for a template, like
/// "Add page after" in the page menu. Until it has been held once on this
/// device, a caption under it says so ("Hold for a template").
class AddPageFooter extends StatefulWidget {
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

  /// The one-time notice id ([SettingsRepository.seenTips]) of the caption.
  static const String holdHint = 'add-page-hold';

  @override
  State<AddPageFooter> createState() => _AddPageFooterState();
}

class _AddPageFooterState extends State<AddPageFooter> {
  /// Whether the caption shows: read once, not on every scroll frame.
  late bool _hint =
      !(AppScope.maybeRead(context)?.settings.seenTips.contains(AddPageFooter.holdHint) ?? true);

  void _addWithTemplate() {
    if (_hint) {
      AppScope.maybeRead(context)?.settings.markTipSeen(AddPageFooter.holdHint);
      setState(() => _hint = false);
    }
    widget.onAddWithTemplate();
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    const height = AddPageFooter.height;
    return ListenableBuilder(
      listenable: Listenable.merge([doc, doc.viewport]),
      builder: (context, _) {
        final page = doc.lastPageOnScreen;
        final size = doc.viewport.size;
        if (doc.flow != PageFlow.continuous || page == null) return const SizedBox.shrink();
        final top = page.bottom + AddPageFooter.gap;
        final bottom = top + height + (_hint ? _captionRoom : 0);
        if (top > size.height || bottom < 0) return const SizedBox.shrink();
        final width = math.min(math.max(page.width * 0.6, 200.0), 360.0);
        return Stack(
          children: [
            Positioned(
              left: page.center.dx - width / 2,
              top: top,
              width: width,
              height: height,
              child: _AddButton(onAdd: widget.onAdd, onAddWithTemplate: _addWithTemplate),
            ),
            if (_hint)
              Positioned(
                left: page.center.dx - width / 2,
                top: top + height + Gaps.xs,
                width: width,
                // A gesture hint: screen readers offer the button's long press.
                child: ExcludeSemantics(
                  child: Text(
                    'Hold for a template',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Room under the button for the caption (inside
/// [DocumentController.footerExtent]).
const double _captionRoom = Gaps.xs + 16;

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onAdd, required this.onAddWithTemplate});

  final VoidCallback onAdd;
  final VoidCallback onAddWithTemplate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A Pencil-edged outline with an Ink +, like the library's New tile.
    return GestureDetector(
      excludeFromSemantics: true, // The button has the long press.
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
