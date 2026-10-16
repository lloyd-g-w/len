import 'dart:ui';

import '../../../app_services.dart';
import '../../../domain/notebook_page.dart';

/// A page drawn on page [index] of a PDF.
typedef PdfPageUse = ({NotebookPage page, int index});

/// What the confirmation of a new PDF under the pages [uses] (whose pages
/// have [sizes]) says about their shapes: " Pages change shape to match."
/// ([NotebookPage.sizeFor]) and, for pages getting shorter, that notes past
/// their new bottom edge will be hidden; empty when no page changes shape.
String pdfReshapeNote(AppServices services, Iterable<PdfPageUse> uses, List<Size> sizes) {
  var reshaped = false, cut = 0;
  for (final u in uses) {
    final size = u.page.sizeFor(sizes[u.index]);
    if (size == u.page.size) continue;
    reshaped = true;
    if (size.height >= u.page.height) continue;
    final content = services.strokes.contentBounds(u.page.id);
    if (content != null && content.bottom > size.height) cut++;
  }
  if (!reshaped) return '';
  return switch (cut) {
    0 => ' Pages change shape to match.',
    1 => ' Pages change shape to match; on 1 page, notes past its new bottom edge will be hidden.',
    _ =>
      ' Pages change shape to match; on $cut pages, notes past their new bottom edge will be '
          'hidden.',
  };
}
