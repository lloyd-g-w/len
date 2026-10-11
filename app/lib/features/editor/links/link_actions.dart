import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/link_target.dart';
import '../chrome/canvas_context_menu.dart';
import '../editor_session.dart';
import '../tools/selection_menu.dart';
import 'link_menu.dart';

/// The selection menu's "Link…": link the selected content to a page or a
/// web address, or remove its link.
SelectionExtraAction linkSelectionAction(BuildContext context, EditorSession session) =>
    SelectionExtraAction('Link…', Icons.link_rounded, (anchor) async {
      final selection = session.content.selection;
      final choice = await showLinkMenu(
        anchor,
        canRemove: selection.elements.any(LinkElements.isLink),
      );
      if (choice == null || !context.mounted) return;
      switch (choice) {
        case LinkChoice.remove:
          session.links.unlinkSelection();
        case LinkChoice.page || LinkChoice.url:
          await session.links.linkSelection(context, url: choice == LinkChoice.url);
      }
    });

/// Lets the PDF text selection menu make links over the selected lines.
void attachPdfLinks(BuildContext context, EditorSession session) {
  final pdf = session.pdf;
  if (pdf == null) return;
  pdf.onLinkSelection = ({required bool url}) {
    final page = pdf.selection.page;
    final rects = pdf.selectionRects;
    if (page == null || rects.isEmpty) return;
    pdf.selection.clear();
    unawaited(session.links.linkRegions(context, page, rects, url: url));
  };
}

/// "Open link" in the canvas menu when a long press lands on a link.
CanvasAction? openLinkAction(BuildContext context, EditorSession session, Offset screen) {
  final hit = session.links.linkAt(screen);
  if (hit == null) return null;
  final target = hit.target;
  return CanvasAction(
    target is UrlLinkTarget ? Icons.open_in_new_rounded : Icons.link_rounded,
    'Go to ${session.links.describe(target)}',
    () => unawaited(session.links.follow(context, target)),
  );
}
