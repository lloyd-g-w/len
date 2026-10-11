import 'dart:ui';

import 'package:pdfrx/pdfrx.dart';

import '../../../data/blob_store.dart';
import '../../../data/search/pdf_text_source.dart';
import '../../documents/pdf/pdf_renderer.dart';

export '../../../data/search/pdf_text_source.dart' show PdfGlyphs;

/// A link on a PDF page: where it is and where it goes.
class PdfLinkArea {
  const PdfLinkArea(this.rects, {this.page, this.url});

  /// Its areas, normalised to the page (0..1 from the left and top edges).
  final List<Rect> rects;

  /// The target page of the same PDF (zero-based), for internal links.
  final int? page;

  /// The target of external links.
  final Uri? url;

  bool contains(Offset normalized) => rects.any((r) => r.contains(normalized));
}

/// An entry of a PDF's outline (bookmarks / table of contents).
class PdfOutlineItem {
  const PdfOutlineItem(this.title, {this.page, this.children = const []});

  final String title;

  /// The page it points at (zero-based, in its PDF), if any.
  final int? page;
  final List<PdfOutlineItem> children;
}

/// Reads text, links and outlines of PDF blobs (an interface so tests can
/// fake PDFium).
abstract interface class PdfInfoSource {
  /// The text of page [page] of PDF [blob] with a box per character, or
  /// null (no text, rotated page, blob not on this device).
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

  Future<PdfPage?> _page(String blob, int index) async {
    if (!await blobs.has(blob)) return null;
    final doc = await renderer.open(blob);
    return index < doc.pages.length ? doc.pages[index] : null;
  }

  @override
  Future<PdfGlyphs?> glyphs(String blob, int page) async {
    final p = await _page(blob, page);
    if (p == null || p.rotation != PdfPageRotation.none || p.width <= 0 || p.height <= 0) {
      return null;
    }
    final raw = await p.loadText();
    if (raw == null || raw.fullText.length != raw.charRects.length) return null;
    return PdfGlyphs(raw.fullText, [for (final r in raw.charRects) _normalized(r, p)]);
  }

  @override
  Future<List<PdfLinkArea>> links(String blob, int page) async {
    final p = await _page(blob, page);
    if (p == null || p.rotation != PdfPageRotation.none || p.width <= 0 || p.height <= 0) {
      return const [];
    }
    return [
      for (final link in await p.loadLinks())
        if (link.url != null || link.dest != null)
          PdfLinkArea(
            [for (final r in link.rects) _normalized(r, p)],
            page: link.dest == null ? null : link.dest!.pageNumber - 1,
            url: link.url,
          ),
    ];
  }

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

  static Rect _normalized(PdfRect r, PdfPage p) => Rect.fromLTRB(
    r.left / p.width,
    1 - r.top / p.height,
    r.right / p.width,
    1 - r.bottom / p.height,
  );
}
