import '../../data/search/search_index.dart';
import '../../domain/notebook.dart';

/// The hits of one notebook, for the library's grouped results.
class NotebookHits {
  NotebookHits(this.notebook, {required this.titleMatches, required this.content});

  final Notebook notebook;

  /// Whether the notebook's title matched.
  final bool titleMatches;

  /// Text box and PDF hits, in page order.
  final List<SearchHit> content;
}

/// Groups [hits] (best first) by notebook, dropping unknown notebooks.
///
/// Notebooks are ordered by their best hit, those whose title matched
/// first; each notebook's content hits are in page order.
List<NotebookHits> groupByNotebook(List<SearchHit> hits, Notebook? Function(String id) notebookOf) {
  final order = <String>[];
  final titles = <String>{};
  final content = <String, List<SearchHit>>{};
  for (final hit in hits) {
    final id = hit.notebookId;
    if (id == null) continue;
    if (!content.containsKey(id)) {
      order.add(id);
      content[id] = [];
    }
    if (hit.kind == SearchHitKind.notebookTitle) {
      titles.add(id);
    } else if (hit.isContent) {
      content[id]!.add(hit);
    }
  }
  final groups = <NotebookHits>[];
  for (final id in order) {
    final notebook = notebookOf(id);
    if (notebook == null) continue;
    final list = content[id]!;
    final rank = {for (final (i, h) in list.indexed) h: i};
    list.sort((a, b) {
      final byPage = (a.pageIndex ?? 0).compareTo(b.pageIndex ?? 0);
      return byPage != 0 ? byPage : rank[a]!.compareTo(rank[b]!);
    });
    groups.add(NotebookHits(notebook, titleMatches: titles.contains(id), content: list));
  }
  // Stable: title matches first, otherwise by best hit.
  final indexed = groups.indexed.toList()
    ..sort((a, b) {
      final t = (b.$2.titleMatches ? 1 : 0) - (a.$2.titleMatches ? 1 : 0);
      return t != 0 ? t : a.$1 - b.$1;
    });
  return [for (final (_, g) in indexed) g];
}

/// "Page 3", or "Canvas" for hits on an infinite canvas.
String hitLocation(SearchHit hit) =>
    hit.pageIndex == null ? 'Canvas' : 'Page ${hit.pageIndex! + 1}';
