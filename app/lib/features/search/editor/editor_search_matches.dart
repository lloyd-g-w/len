import 'dart:ui';

import '../../../data/search/search_index.dart';
import '../../../data/search/search_query.dart';
import '../../../data/search/search_service.dart';
import '../../../domain/notebook_page.dart';
import 'editor_search_host.dart';
import 'ink_match_rects.dart';
import 'text_match_rects.dart';

/// One match in the open notebook: a text box, or one occurrence in a
/// PDF page's text or a recognised line of handwriting.
class EditorSearchMatch {
  EditorSearchMatch({
    required this.hit,
    required this.range,
    this.box,
    this.pdf,
    this.pageSize,
    this.inkRects,
    this.textRects,
  });

  final SearchHit hit;

  /// Where the match is in [SearchHit.body].
  final ({int start, int end}) range;

  /// The text box (page coordinates; rotation about its centre).
  final ({Rect rect, double rotation})? box;

  /// The PDF page the text is on.
  final PageBackground? pdf;

  /// Size of the page (for PDF glyph boxes, which are normalised).
  final Size? pageSize;

  /// The ink to highlight for a handwriting match: the matched words, or
  /// the whole line (page coordinates). [box] is their union.
  final List<Rect>? inkRects;

  /// The lines of a text box match (page coordinates, rotated with the
  /// box); [box] is the whole box.
  final List<RotatedRect>? textRects;

  String get surfaceId => hit.surfaceId!;
  int? get pageIndex => hit.pageIndex;
}

/// The matches of [query] ([parsed]) in notebook [notebookId], in reading
/// order ([limit] at most, give or take one hit's occurrences), placed on
/// the pages [host] shows.
List<EditorSearchMatch> findEditorSearchMatches(
  SearchService search,
  EditorSearchHost host,
  SearchQuery parsed, {
  required String query,
  required String notebookId,
  required int limit,
}) {
  final hits = search.search(query, notebookId: notebookId);
  final matches = <EditorSearchMatch>[];
  for (final hit in hits) {
    if (!hit.isContent || hit.surfaceId == null) continue;
    final page = host.pageOf(hit.surfaceId!);
    if (hit.kind == SearchHitKind.text) {
      final ranges = parsed.ranges(hit.body);
      final stored = search.index.elementBox(hit.refId);
      if (stored == null) continue;
      final box = (rect: stored.rect, rotation: stored.rotation);
      final words = ranges.isEmpty
          ? null
          : textMatchRects(
              json: stored.data,
              box: stored.rect,
              rotation: stored.rotation,
              body: hit.body,
              ranges: ranges,
            );
      if (words == null) {
        // The whole box (its text not matched word by word).
        matches.add(
          EditorSearchMatch(
            hit: hit,
            range: ranges.isEmpty ? (start: 0, end: 0) : ranges.first,
            box: box,
          ),
        );
      } else {
        // One match per occurrence, highlighted where the box shows it.
        for (final (i, range) in ranges.indexed) {
          if (words[i].isEmpty) continue;
          matches.add(EditorSearchMatch(hit: hit, range: range, box: box, textRects: words[i]));
        }
      }
    } else if (hit.kind == SearchHitKind.handwriting) {
      final boxes = search.index.inkTextBoxes(hit.refId);
      if (boxes == null) continue;
      for (final range in parsed.ranges(hit.body)) {
        final rects = InkMatchRects.of(hit.body, range, boxes.line, boxes.words);
        matches.add(
          EditorSearchMatch(
            hit: hit,
            range: range,
            box: (rect: rects.reduce((a, b) => a.expandToInclude(b)), rotation: 0.0),
            inkRects: rects,
          ),
        );
      }
    } else {
      for (final range in parsed.ranges(hit.body)) {
        matches.add(
          EditorSearchMatch(hit: hit, range: range, pdf: page?.pdf, pageSize: page?.size),
        );
      }
    }
    if (matches.length >= limit) break;
  }
  matches.sort(_inReadingOrder);
  return matches;
}

/// Page order; on a page, PDF text first (in text order), then text
/// boxes from top to bottom.
int _inReadingOrder(EditorSearchMatch a, EditorSearchMatch b) {
  final page = (a.pageIndex ?? 0).compareTo(b.pageIndex ?? 0);
  if (page != 0) return page;
  // Occurrences in one text box (or PDF page, or line) in text order.
  if (identical(a.hit, b.hit)) return a.range.start.compareTo(b.range.start);
  final ab = a.box, bb = b.box;
  if (ab == null || bb == null) {
    if (ab != null) return 1;
    if (bb != null) return -1;
    return a.range.start.compareTo(b.range.start);
  }
  final y = ab.rect.top.compareTo(bb.rect.top);
  return y != 0 ? y : ab.rect.left.compareTo(bb.rect.left);
}
