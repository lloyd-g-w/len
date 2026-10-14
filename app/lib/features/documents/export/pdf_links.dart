import 'dart:ui' show Rect;

import 'package:pdf/pdf.dart';

import '../../../domain/link_target.dart';
import '../../../domain/paper_pattern.dart';
import '../../../domain/pdf_page_space.dart';
import 'pdf_export.dart';

/// Writes the links of exported pages as PDF link annotations:
///
/// - link elements: web addresses as URI actions, links to pages that are
///   part of the export as GoTo actions to named destinations;
/// - planner links (a day on a month, a week, …) to the first exported
///   page with that planner template;
/// - the links of imported PDF pages (`backgroundLinks`, normalised to the
///   page): web links as they are, links to a page of the same PDF to the
///   exported page showing it (the next one after the link's page if the
///   PDF appears more than once).
///
/// Links to other notebooks, or to pages left out of the export, are
/// dropped. Annotations have no border, so the page looks as it does in
/// the app.
abstract final class PdfLinkWriter {
  /// Annotates [written] (the PDF pages of [pages], in order);
  /// [backgroundLinks] are the links of each page's PDF background.
  static void write(
    PdfDocument doc,
    List<ExportPage> pages,
    List<PdfPage> written, [
    List<List<PdfLinkArea>> backgroundLinks = const [],
  ]) {
    final indexOf = {for (final (i, p) in pages.indexed) p.page.id: i};
    final named = <int>{};
    const k = PdfExporter.pointsPerUnit;

    void goTo(int from, int to, PdfRect rect) {
      final name = destinationOf(to);
      if (named.add(to)) doc.pdfNames.addDest(name, written[to], posY: pages[to].page.height * k);
      PdfAnnot(written[from], PdfAnnotNamedLink(rect: rect, dest: name));
    }

    void url(int from, Uri uri, PdfRect rect) =>
        PdfAnnot(written[from], PdfAnnotUrlLink(rect: rect, url: uri.toString()));

    for (final (i, export) in pages.indexed) {
      final page = export.page;
      // World units (y down) to PDF points (y up).
      PdfRect world(Rect b) =>
          PdfRect(b.left * k, (page.height - b.bottom) * k, b.width * k, b.height * k);

      for (final e in export.elements) {
        switch (LinkElements.targetOf(e)) {
          case UrlLinkTarget(:final uri):
            url(i, uri, world(e.bounds));
          case PageLinkTarget(:final pageId):
            if (indexOf[pageId] case final j?) goTo(i, j, world(e.bounds));
          case null:
        }
      }

      if (page.paper.style.isPlanner) {
        final pattern = PaperPattern.of(page.paper, page.bounds, page: page.bounds);
        for (final link in pattern.links) {
          final j = pages.indexWhere((p) => p.page.paper.sameSheet(link.target));
          if (j >= 0 && j != i) goTo(i, j, world(link.rect));
        }
      }

      final pdf = page.pdf;
      if (pdf == null || i >= backgroundLinks.length) continue;
      for (final link in backgroundLinks[i]) {
        final target = link.page;
        final j = target == null ? null : _exportedPage(pages, i, pdf.blob, target);
        for (final r in link.rects) {
          final rect = world(
            Rect.fromLTRB(
              r.left * page.width,
              r.top * page.height,
              r.right * page.width,
              r.bottom * page.height,
            ),
          );
          if (link.url case final uri?) {
            url(i, uri, rect);
          } else if (j != null) {
            goTo(i, j, rect);
          }
        }
      }
    }
  }

  /// The exported page showing page [pdfPage] of PDF [blob]: the first
  /// after page [from], wrapping around; null if none is exported.
  static int? _exportedPage(List<ExportPage> pages, int from, String blob, int pdfPage) {
    for (var n = 1; n <= pages.length; n++) {
      final j = (from + n) % pages.length;
      final bg = pages[j].page.pdf;
      if (bg != null && bg.blob == blob && bg.pageIndex == pdfPage) return j;
    }
    return null;
  }

  /// The named destination of exported page [index].
  static String destinationOf(int index) => 'page-${index + 1}';
}
