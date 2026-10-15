import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import '../links/link_menu.dart';
import 'pdf_highlight_removal.dart';
import 'pdf_highlight_swatches.dart';
import 'pdf_interaction.dart';
import 'pdf_selection_paint.dart';

/// The PDF text selection's menu (copy, highlight in one of the
/// highlighter's quick colours, remove a highlight over it, open or make a
/// link, select all), above the selected lines (below them if there is no
/// room above). It is placed anew whenever [relayout] notifies (the view
/// moved) without being rebuilt.
class PdfSelectionMenu extends StatelessWidget {
  const PdfSelectionMenu({
    super.key,
    required this.interaction,
    required this.relayout,
    required this.onPress,
    required this.onCopy,
    required this.onHighlight,
  });

  final PdfInteraction interaction;
  final Listenable relayout;

  /// A pointer went down on the menu (before its buttons hear it).
  final VoidCallback onPress;
  final VoidCallback onCopy;

  /// Highlights the selection in the given colour.
  final ValueChanged<int> onHighlight;

  /// The box around the selected lines on screen.
  Rect _selectionOnScreen() {
    final doc = interaction.doc;
    final index = doc.pages.indexWhere((p) => p.id == interaction.selection.page?.id);
    final frame = index < 0 ? null : doc.layout.frameOf(index);
    if (frame == null) return Rect.zero;
    final rects = [
      for (final r in interaction.selectionRects)
        Rect.fromPoints(
          doc.viewport.toScreen(frame.topLeft + r.topLeft),
          doc.viewport.toScreen(frame.topLeft + r.bottomRight),
        ),
    ];
    return rects.isEmpty ? Rect.zero : rects.reduce((a, b) => a.expandToInclude(b));
  }

  /// Windows narrower than this show Copy without its label, and a glyph
  /// for Highlight.
  static const double _labelledWidth = 480;

  @override
  Widget build(BuildContext context) {
    final roomAbove = MediaQuery.paddingOf(context).top + 64;
    // Phones: Copy without its label, so the colours and a link fit.
    final labelled = MediaQuery.sizeOf(context).width >= _labelledWidth;
    final copy = !labelled
        ? IconButton(
            key: const ValueKey('pdf-copy'),
            tooltip: 'Copy',
            icon: const Icon(Symbols.content_copy_sharp, size: Glyphs.bar),
            onPressed: onCopy,
          )
        : TextButton.icon(
            key: const ValueKey('pdf-copy'),
            onPressed: onCopy,
            icon: const Icon(Symbols.content_copy_sharp, size: Glyphs.menu),
            label: const Text('Copy'),
          );
    final highlighted = interaction.selectionHighlighted;
    return CustomSingleChildLayout(
      delegate: PdfMenuPlacement(_selectionOnScreen, roomAbove: roomAbove, relayout: relayout),
      // Moved, not repainted, as the view moves.
      child: RepaintBoundary(
        child: Listener(
          onPointerDown: (_) => onPress(),
          // A floating panel like the ink selection menu (the pill is the
          // page indicator's only).
          child: FloatingPanel(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                copy,
                PdfHighlightSwatches(
                  tools: interaction.tools,
                  onHighlight: onHighlight,
                  labelled: labelled,
                  // Room for Remove highlight on a phone.
                  count: highlighted && !labelled
                      ? PdfHighlightSwatches.max - 1
                      : PdfHighlightSwatches.max,
                ),
                if (highlighted)
                  IconButton(
                    key: const ValueKey('pdf-remove-highlight'),
                    tooltip: 'Remove highlight',
                    icon: const Icon(Symbols.format_color_reset_sharp, size: Glyphs.bar),
                    onPressed: interaction.removeSelectedHighlights,
                  ),
                if (interaction.selectedLink != null)
                  IconButton(
                    key: const ValueKey('pdf-open-link'),
                    tooltip: 'Open link',
                    icon: const Icon(Symbols.open_in_new_sharp, size: Glyphs.bar),
                    onPressed: interaction.openSelectedLink,
                  ),
                if (interaction.onLinkSelection case final link?)
                  Builder(
                    builder: (anchor) => IconButton(
                      key: const ValueKey('pdf-link'),
                      tooltip: 'Link…',
                      icon: const Icon(Symbols.link_sharp, size: Glyphs.bar),
                      onPressed: () async {
                        final choice = await showLinkMenu(anchor);
                        if (choice != null) link(url: choice == LinkChoice.url);
                      },
                    ),
                  ),
                IconButton(
                  key: const ValueKey('pdf-select-all'),
                  tooltip: 'Select all on page',
                  icon: const Icon(Symbols.select_all_sharp, size: Glyphs.bar),
                  onPressed: interaction.selectAll,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
