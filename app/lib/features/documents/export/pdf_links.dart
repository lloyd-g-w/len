import 'package:pdf/pdf.dart';

import '../../../domain/link_target.dart';
import 'pdf_export.dart';

/// Writes the link elements of exported pages as PDF link annotations:
/// web addresses as URI actions, links to pages that are part of the
/// export as GoTo actions to named destinations (links to other notebooks,
/// or to pages left out of the export, are dropped). Annotations have no
/// border, so the page looks as it does in the app.
abstract final class PdfLinkWriter {
  /// Annotates [written] (the PDF pages of [pages], in order).
  static void write(PdfDocument doc, List<ExportPage> pages, List<PdfPage> written) {
    final indexOf = {for (final (i, p) in pages.indexed) p.page.id: i};
    final named = <int>{};
    for (final (i, export) in pages.indexed) {
      final height = export.page.height;
      for (final e in export.elements) {
        final target = LinkElements.targetOf(e);
        if (target == null) continue;
        const k = PdfExporter.pointsPerUnit;
        final b = e.bounds;
        final rect = PdfRect(b.left * k, (height - b.bottom) * k, b.width * k, b.height * k);
        switch (target) {
          case UrlLinkTarget(:final uri):
            PdfAnnot(written[i], PdfAnnotUrlLink(rect: rect, url: uri.toString()));
          case PageLinkTarget(:final pageId):
            final j = indexOf[pageId];
            if (j == null) continue;
            final name = destinationOf(j);
            if (named.add(j)) {
              doc.pdfNames.addDest(name, written[j], posY: pages[j].page.height * k);
            }
            PdfAnnot(written[i], PdfAnnotNamedLink(rect: rect, dest: name));
        }
      }
    }
  }

  /// The named destination of exported page [index].
  static String destinationOf(int index) => 'page-${index + 1}';
}
