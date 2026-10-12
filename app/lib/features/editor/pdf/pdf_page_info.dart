import 'package:pdfrx/pdfrx.dart';

import '../../../data/blob_store.dart';
import '../../../data/search/pdf_text_source.dart';
import '../../../domain/pdf_page_space.dart';
import '../../documents/pdf/pdf_renderer.dart';

export '../../../data/search/pdf_text_source.dart' show PdfGlyphs, PdfTextDirection, PdfTextLine;
export '../../../domain/pdf_page_space.dart' show PdfLinkArea;

/// An entry of a PDF's outline (bookmarks / table of contents).
class PdfOutlineItem {
  const PdfOutlineItem(this.title, {this.page, this.children = const []});

  final String title;

  /// The page it points at (zero-based, in its PDF), if any.
  final int? page;
  final List<PdfOutlineItem> children;
}

/// Reads text, links and outlines of PDF blobs (an interface so tests can
/// fake PDFium). Boxes and link areas are normalised to the page as shown
/// (its `/Rotate` applied).
abstract interface class PdfInfoSource {
  /// The text of page [page] of PDF [blob] with a box per character, or
  /// null (no text, blob not on this device).
  Future<PdfGlyphs?> glyphs(String blob, int page);

  /// The links of page [page] of PDF [blob].
  Future<List<PdfLinkArea>> links(String blob, int page);

  /// The outline of PDF [blob] (empty if it has none).
  Future<List<PdfOutlineItem>> outline(String blob);
}

/// [PdfInfoSource] reading the documents a [PdfRenderer] opened for the
/// editor's backgrounds (no second copy of the PDF is opened).
class PdfrxInfoSource implements PdfInfoSource {
  PdfrxInfoSource(this.renderer, this.blobs);

  final PdfRenderer renderer;
  final BlobStore blobs;

  @override
  Future<PdfGlyphs?> glyphs(String blob, int page) async {
    if (!await blobs.has(blob)) return null;
    final doc = await renderer.open(blob);
    return page < doc.pages.length ? pdfiumGlyphs(doc.pages[page]) : null;
  }

  @override
  Future<List<PdfLinkArea>> links(String blob, int page) async =>
      await blobs.has(blob) ? renderer.links(blob, page) : const [];

  @override
  Future<List<PdfOutlineItem>> outline(String blob) async {
    if (!await blobs.has(blob)) return const [];
    final doc = await renderer.open(blob);
    List<PdfOutlineItem> convert(List<PdfOutlineNode> nodes) => [
      for (final n in nodes)
        PdfOutlineItem(
          n.title.trim(),
          page: n.dest == null ? null : n.dest!.pageNumber - 1,
          children: convert(n.children),
        ),
    ];
    return convert(await doc.loadOutline());
  }
}
