import 'package:flutter/foundation.dart' show mergeSort;
import 'package:pdf/pdf.dart';

import '../../../domain/outline/outline_tree.dart';

/// A bookmark of an exported PDF: an outline entry opening exported page
/// [page] (zero-based in the export), with the entries nested under it.
class ExportBookmark {
  const ExportBookmark(this.title, this.page, [this.children = const []]);

  final String title;
  final int page;
  final List<ExportBookmark> children;
}

/// The bookmarks of a notebook's outline [tree] for an export of the pages
/// whose ids map to their index in [exported] (UX_AUDIT R22-3). Entries
/// of pages left out are dropped and their children move up to take
/// their place (in page order among the entries there), so every exported
/// entry stays reachable.
List<ExportBookmark> exportBookmarks(OutlineTree tree, Map<String, int> exported) {
  List<ExportBookmark> under(String? parent) {
    var moved = false;
    final out = <ExportBookmark>[];
    for (final e in tree.childrenOf(parent)) {
      final page = exported[e.pageId];
      if (page != null) {
        out.add(ExportBookmark(e.title, page, under(e.id)));
      } else {
        moved = true;
        out.addAll(under(e.id));
      }
    }
    // Stable: entries of one page keep the outline's order.
    if (moved) mergeSort(out, compare: (a, b) => a.page.compareTo(b.page));
    return out;
  }

  return under(null);
}

/// Writes [bookmarks] as the outline of [doc], each opening its page of
/// [pages] (the written PDF pages, in export order).
void writeBookmarks(PdfDocument doc, List<ExportBookmark> bookmarks, List<PdfPage> pages) {
  void add(PdfOutline parent, List<ExportBookmark> items) {
    for (final b in items) {
      if (b.page < 0 || b.page >= pages.length) continue;
      final node = PdfOutline(doc, title: b.title, dest: pages[b.page]);
      parent.add(node);
      add(node, b.children);
    }
  }

  if (bookmarks.isNotEmpty) add(doc.outline, bookmarks);
}
