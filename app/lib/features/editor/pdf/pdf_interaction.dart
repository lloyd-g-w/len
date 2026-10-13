import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../core/clock.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../../../ink/tools/lasso_tool.dart';
import '../../../ink/undo_history.dart';
import '../document/document_controller.dart';
import 'pdf_highlights.dart';
import 'pdf_page_info.dart';
import 'pdf_page_info_cache.dart';
import 'pdf_text_selection.dart';

/// A point on a PDF page of the document.
typedef PdfPagePoint = ({int index, NotebookPage page, PageBackground pdf, Offset normalized});

/// A character of the PDF text of the document's page [index].
typedef PdfTextPoint = ({int index, NotebookPage page, PdfGlyphs glyphs, int glyph});

/// The interactive side of imported PDF pages in one paged editor: text
/// selection (a long press or right click, or the lasso: [LassoText]; then
/// the handles), copying, highlighting the selection with highlighter
/// strokes, links and the outline.
class PdfInteraction extends ChangeNotifier implements LassoText {
  PdfInteraction({
    required this.doc,
    required this.tools,
    required this.info,
    this.clock = const Clock(),
  }) {
    doc.addListener(_onDocument);
    _onDocument();
  }

  final DocumentController doc;
  final ToolSettings tools;
  final Clock clock;

  /// Text and links of the PDF pages (shared by the notebook's views;
  /// not disposed here).
  final PdfPageInfoCache info;
  final PdfSelection selection = PdfSelection();

  /// Follows a link (set by the editor: jump to a page, or confirm and
  /// open a web address).
  void Function(PdfLinkArea link, PageBackground from)? onLink;

  /// Makes a link over the selected text (set by the editor): [url] a web
  /// address, else a page.
  void Function({required bool url})? onLinkSelection;

  /// The selected lines in the selection's page's world coordinates.
  List<Rect> get selectionRects {
    final page = selection.page;
    if (page == null) return const [];
    final size = page.size;
    return [
      for (final r in selection.rects)
        Rect.fromLTRB(
          r.left * size.width,
          r.top * size.height,
          r.right * size.width,
          r.bottom * size.height,
        ),
    ];
  }

  List<NotebookPage>? _pages;

  /// Whether the notebook has imported PDF pages.
  bool get hasPdf => doc.pages.any((p) => p.background != null);

  /// The PDFs of the notebook, in the order their first pages appear.
  List<String> get blobs => {for (final p in doc.pages) ?p.background?.blob}.toList();

  void _onDocument() {
    if (identical(doc.pages, _pages)) return;
    _pages = doc.pages;
    final ids = {for (final p in doc.pages) p.id};
    if (selection.spans.any((s) => !ids.contains(s.page.id))) selection.clear();
  }

  /// The PDF page under [screen] and the normalised position on it.
  PdfPagePoint? pageAt(Offset screen) {
    final world = doc.viewport.toWorld(screen);
    final index = doc.layout.pageAt(world);
    if (index == null) return null;
    final page = doc.pages[index];
    final pdf = page.background;
    final frame = doc.layout.frameOf(index);
    if (pdf == null || frame == null) return null;
    final local = world - frame.topLeft;
    return (
      index: index,
      page: page,
      pdf: pdf,
      normalized: Offset(local.dx / frame.width, local.dy / frame.height),
    );
  }

  /// The link under [screen], if its page's links have loaded.
  PdfLinkArea? linkAt(Offset screen) {
    final at = pageAt(screen);
    if (at == null) return null;
    for (final link in info.links(at.pdf.blob, at.pdf.pageIndex)) {
      if (link.contains(at.normalized)) return link;
    }
    return null;
  }

  /// Follows the link under [screen]; returns whether there was one.
  bool followLinkAt(Offset screen) {
    final link = linkAt(screen);
    final at = pageAt(screen);
    if (link == null || at == null) return false;
    onLink?.call(link, at.pdf);
    return true;
  }

  /// Where the selection's start and end handles are on screen: where its
  /// first line starts (at the top of its letters: the top-left for
  /// upright text, the top-right on a page turned clockwise, …) and where
  /// its last line ends.
  /// The start is on the selection's first page, the end on its last.
  (Offset, Offset)? get handleEnds {
    final spans = selection.spans.where((s) => !s.isEmpty).toList();
    if (spans.isEmpty) return null;
    final first = spans.first.lines, last = spans.last.lines;
    if (first.isEmpty || last.isEmpty) return null;
    final a = toScreen(spans.first.page, first.first.startCorner);
    final b = toScreen(spans.last.page, last.last.endCorner);
    return a == null || b == null ? null : (a, b);
  }

  /// Where normalised point [n] of [page] is on screen; null if the page
  /// is not laid out.
  Offset? toScreen(NotebookPage page, Offset n) {
    final index = doc.pages.indexWhere((p) => p.id == page.id);
    final frame = index < 0 ? null : doc.layout.frameOf(index);
    if (frame == null) return null;
    return doc.viewport.toScreen(frame.topLeft + Offset(n.dx * frame.width, n.dy * frame.height));
  }

  /// The character nearest to [screen] on the PDF page under it (or the
  /// nearest page's, between pages); null off PDF text.
  PdfTextPoint? textPointAt(Offset screen) {
    final world = doc.viewport.toWorld(screen);
    final index = doc.layout.pageAt(world) ?? doc.layout.nearestPage(world);
    if (index == null) return null;
    final page = doc.pages[index];
    final bg = page.background;
    final frame = doc.layout.frameOf(index);
    final glyphs = bg == null ? null : info.glyphs(bg.blob, bg.pageIndex);
    if (frame == null || glyphs == null) return null;
    final local = world - frame.topLeft;
    final glyph = glyphs.nearestIndex(Offset(local.dx / frame.width, local.dy / frame.height));
    return glyph == null ? null : (index: index, page: page, glyphs: glyphs, glyph: glyph);
  }

  /// Selects from character [a] to character [b] (in either order, on
  /// the same page or not; both included); PDF pages between them are
  /// selected whole (as far as their text has loaded).
  void selectRange(PdfTextPoint a, PdfTextPoint b, {bool menu = false}) {
    final before = a.index < b.index || (a.index == b.index && a.glyph <= b.glyph);
    final (from, to) = before ? (a, b) : (b, a);
    if (from.index == to.index) {
      selection.select(from.page, from.glyphs, from.glyph, to.glyph + 1, menu: menu);
      return;
    }
    final spans = [
      PdfSpan(from.page, from.glyphs, from.glyph, from.glyphs.text.length),
      for (var i = from.index + 1; i < to.index; i++)
        if (doc.pages[i].background case final bg?)
          if (info.glyphs(bg.blob, bg.pageIndex) case final glyphs?)
            PdfSpan(doc.pages[i], glyphs, 0, glyphs.text.length),
      PdfSpan(to.page, to.glyphs, 0, to.glyph + 1),
    ];
    selection.selectSpans(spans, menu: menu);
  }

  /// The link under the start of the selection, if any (its menu offers to
  /// open it: a long press on a link selects its text).
  PdfLinkArea? get selectedLink {
    final bg = selection.page?.background;
    if (bg == null || selection.isEmpty) return null;
    final at = selection.rects.first.center;
    for (final link in info.links(bg.blob, bg.pageIndex)) {
      if (link.contains(at)) return link;
    }
    return null;
  }

  /// Follows [selectedLink] and drops the selection.
  void openSelectedLink() {
    final link = selectedLink;
    final bg = selection.page?.background;
    if (link == null || bg == null) return;
    selection.clear();
    onLink?.call(link, bg);
  }

  /// Whether a character of PDF text lies under [screen] (or just beside
  /// it on its line).
  @override
  bool hasTextAt(Offset screen) {
    final at = pageAt(screen);
    if (at == null) return false;
    return info.glyphs(at.pdf.blob, at.pdf.pageIndex)?.indexAt(at.normalized, slop: 0.005) != null;
  }

  /// Selects the text from the character nearest [from] to the one nearest
  /// [to] (a lasso drag), offering the menu when [done].
  @override
  void selectBetween(Offset from, Offset to, {required bool done}) {
    final a = textPointAt(from), b = textPointAt(to);
    if (a != null && b != null) selectRange(a, b, menu: done);
  }

  /// Selects the word under [screen] and offers the menu (long press, a
  /// lasso tap); returns whether there was text there.
  @override
  bool selectWordAt(Offset screen) {
    final at = pageAt(screen);
    if (at == null) return false;
    final glyphs = info.glyphs(at.pdf.blob, at.pdf.pageIndex);
    final i = glyphs?.indexAt(at.normalized);
    if (glyphs == null || i == null) return false;
    final (start, end) = glyphs.wordAt(i);
    selection.select(at.page, glyphs, start, end, menu: true);
    return true;
  }

  /// Selects all the text of the selection's page.
  void selectAll() {
    final page = selection.page, glyphs = selection.glyphs;
    if (page == null || glyphs == null) return;
    selection.select(page, glyphs, 0, glyphs.text.length, menu: true);
  }

  /// The page of the notebook showing page [pdfPage] of PDF [blob] — the
  /// one after [from] when the PDF appears more than once — or null.
  int? notebookPageOf(String blob, int pdfPage, {String? from}) {
    final pages = doc.pages;
    final start = from == null ? 0 : pages.indexWhere((p) => p.id == from).clamp(0, pages.length);
    for (var k = 0; k < pages.length; k++) {
      final i = (start + k) % pages.length;
      final bg = pages[i].background;
      if (bg != null && bg.blob == blob && bg.pageIndex == pdfPage) return i;
    }
    return null;
  }

  /// Covers the selected lines with highlighter strokes in [color] (by
  /// default the highlighter's current colour) and the highlighter's
  /// opacity, as one undoable edit; clears the selection. Returns how many
  /// strokes were added.
  int highlightSelection({int? color}) {
    if (selection.isEmpty) return 0;
    final ink = color ?? tools.configOf(InkTool.highlighter).color;
    final style = tools.styleFor(InkTool.highlighter).copyWith(thinning: 0, streamline: 0);
    final now = clock.nowMs();
    var added = 0;
    // Each page gets its own strokes (on a selection over several pages),
    // one undo step for all.
    doc.surfaces.models.group(() {
      for (final span in selection.spans) {
        final page = span.page;
        final strokes = [
          for (final line in span.lines)
            ?PdfHighlights.stroke(
              line,
              page,
              id: clock.newId(),
              color: ink,
              style: style,
              createdAt: now,
            ),
        ];
        if (strokes.isEmpty) continue;
        doc.surfaces.surfaceOf(page.id).model.commit(InkEdit(added: strokes));
        added += strokes.length;
      }
    });
    selection.clear();
    return added;
  }

  @override
  void dispose() {
    doc.removeListener(_onDocument);
    selection.dispose();
    super.dispose();
  }
}
