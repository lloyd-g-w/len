part of 'editor_search_controller.dart';

/// Finding the matches and bringing one into view.
extension _SearchReveal on EditorSearchController {
  /// Re-runs the search for [_query].
  void _run() {
    _parsed = SearchQuery(_query);
    final previous = currentMatch;
    final matches = findEditorSearchMatches(
      search,
      host,
      _parsed,
      query: _query,
      notebookId: notebookId,
      limit: EditorSearchController.maxMatches,
    );
    _matches = matches;
    // Stay on the same match when results are refreshed.
    _current = previous == null
        ? -1
        : matches.indexWhere(
            (m) => m.hit.refId == previous.hit.refId && m.range.start == previous.range.start,
          );
  }

  void _reveal(EditorSearchMatch match) {
    if (!host.isReady) {
      _revealWhenReady = match;
      host.changes.addListener(_onHostChanged);
      return;
    }
    final rects = rectsOf(match);
    if (rects.isNotEmpty) {
      _refineWhenLoaded = null;
      host.reveal(match.surfaceId, _union(rects), clear: clear);
      return;
    }
    // PDF glyphs not loaded yet: show the page's top now, the exact spot
    // once they are.
    final size = match.pageSize ?? Size.zero;
    _refineWhenLoaded = match.pdf == null ? null : match;
    host.reveal(match.surfaceId, Offset.zero & Size(size.width, 1), clear: clear);
  }

  /// Brings [match] (or else the first match) into view once the bar has
  /// been laid out, so it lands below the bar's measured height.
  void _showAfterLayout(EditorSearchMatch? match) {
    final target = match ?? (_matches.isEmpty ? null : _matches.first);
    if (target == null) return;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        if (_disposed || !_open || !_matches.contains(target)) return;
        if (currentMatch == null || currentMatch == target) _reveal(target);
      })
      ..scheduleFrame();
  }

  static Rect _union(List<({Rect rect, double rotation})> rects) =>
      rects.skip(1).fold(rects.first.rect, (u, r) => u.expandToInclude(r.rect));
}
