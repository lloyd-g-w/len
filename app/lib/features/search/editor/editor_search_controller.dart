import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter/scheduler.dart';

import '../../../app_services.dart';
import '../../../data/search/search_query.dart';
import '../../../data/search/search_service.dart';
import '../../../ink/viewport.dart';
import '../../editor/document/document_controller.dart';
import '../../editor/editor_session.dart';
import 'editor_search_host.dart';
import 'editor_search_matches.dart';
import 'pdf_glyph_cache.dart';

export 'editor_search_matches.dart' show EditorSearchMatch;

part 'editor_search_reveal.dart';

/// State of the in-notebook search (Ctrl+F): the query, its matches in
/// page order, the current match, and moving between them — revealing
/// each through an [EditorSearchHost].
///
/// Also takes "show this result" requests from the library
/// ([SearchService.requestJump]) for its notebook.
class EditorSearchController extends ChangeNotifier {
  EditorSearchController({
    required this.search,
    required this.notebookId,
    required this.host,
    required this.glyphs,
    this.clear = const EdgeInsets.only(top: 132),
  }) {
    search.addListener(_onSearchChanged);
    glyphs.addListener(_onGlyphs);
    _takeJump();
  }

  /// The search for an editor [session] (paged or canvas).
  factory EditorSearchController.forSession(
    AppServices services,
    EditorSession session, {
    required String notebookId,
  }) => switch (session.doc) {
    final doc? => EditorSearchController.forDocument(services, doc, notebookId: notebookId),
    null => EditorSearchController.forCanvas(
      services,
      session.canvasViewport!,
      notebookId: notebookId,
    ),
  };

  /// The search for a paged notebook shown by [doc].
  factory EditorSearchController.forDocument(
    AppServices services,
    DocumentController doc, {
    required String notebookId,
  }) => EditorSearchController(
    search: services.search,
    notebookId: notebookId,
    host: DocumentSearchHost(doc),
    glyphs: _glyphCache(services),
  );

  /// The search for an infinite canvas seen through [viewport].
  factory EditorSearchController.forCanvas(
    AppServices services,
    ViewportController viewport, {
    required String notebookId,
  }) => EditorSearchController(
    search: services.search,
    notebookId: notebookId,
    host: CanvasSearchHost(viewport, surfaceId: notebookId),
    glyphs: _glyphCache(services),
  );

  static PdfGlyphCache _glyphCache(AppServices services) => PdfGlyphCache(
    readBlob: (sha) async =>
        await services.blobs.read(sha) ??
        (await services.sync.fetchBlob(sha) ? await services.blobs.read(sha) : null),
  );

  final SearchService search;
  final String notebookId;
  final EditorSearchHost host;
  final PdfGlyphCache glyphs;

  /// Screen edges covered by the editor's chrome and the search bar;
  /// revealed matches are kept clear of them.
  EdgeInsets clear;

  /// Most matches listed (a very common word in a long PDF).
  static const int maxMatches = 1000;

  static const _debounce = Duration(milliseconds: 150);

  bool _open = false;
  String _query = '';
  SearchQuery _parsed = SearchQuery('');
  List<EditorSearchMatch> _matches = const [];
  int _current = -1;
  int _focusRequests = 0;
  Timer? _timer;
  EditorSearchMatch? _revealWhenReady;
  EditorSearchMatch? _refineWhenLoaded;
  bool _disposed = false;

  bool get isOpen => _open;
  String get query => _query;
  SearchQuery get parsedQuery => _parsed;
  List<EditorSearchMatch> get matches => _matches;

  /// Index of the current match in [matches], or -1 before navigating.
  int get current => _current;
  EditorSearchMatch? get currentMatch => _current < 0 ? null : _matches[_current];

  /// Increases whenever the search field should take focus.
  int get focusRequests => _focusRequests;

  /// Opens the search bar (focusing its field) and searches [query] (or
  /// the previous query) right away.
  void open({String? query}) {
    _open = true;
    _focusRequests++;
    _query = query ?? _query;
    // Refresh: text may have been edited since the last search.
    if (_query.trim().isNotEmpty) _run();
    _showAfterLayout(currentMatch);
    notifyListeners();
  }

  void close() {
    if (!_open) return;
    _open = false;
    _timer?.cancel();
    host.releaseRoom();
    notifyListeners();
  }

  /// Updates the query; matches follow shortly (debounced while typing).
  void setQuery(String value) {
    if (value == _query) return;
    _query = value;
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      if (_disposed) return;
      _run();
      _showAfterLayout(currentMatch);
      notifyListeners();
    });
  }

  void next() => select(_matches.isEmpty ? -1 : (_current + 1) % _matches.length);

  void previous() =>
      select(_matches.isEmpty ? -1 : (_current - 1 + _matches.length) % _matches.length);

  /// Makes match [index] current and brings it into view.
  void select(int index) {
    if (index < 0 || index >= _matches.length) return;
    _current = index;
    _reveal(_matches[index]);
    _showAfterLayout(_matches[index]); // Again if the bar changed height.
    notifyListeners();
  }

  /// Rectangles (with rotation, page coordinates) to highlight for
  /// [match]; PDF text boxes load on demand, so they may come later.
  List<({Rect rect, double rotation})> rectsOf(EditorSearchMatch match) {
    if (match.inkRects case final rects?) {
      return [for (final r in rects) (rect: r.inflate(2), rotation: 0.0)];
    }
    if (match.textRects case final rects?) {
      return [for (final r in rects) (rect: r.rect.inflate(1), rotation: r.rotation)];
    }
    if (match.box case final box?) return [box];
    final pdf = match.pdf;
    final size = match.pageSize;
    if (pdf == null || size == null) return const [];
    final page = glyphs.glyphs(pdf.blob, pdf.pageIndex);
    if (page == null || page.text != match.hit.body) return const [];
    return [
      for (final r in page.rectsFor(match.range.start, match.range.end))
        (
          rect: Rect.fromLTRB(
            r.left * size.width,
            r.top * size.height,
            r.right * size.width,
            r.bottom * size.height,
          ).inflate(1.5),
          rotation: 0.0,
        ),
    ];
  }

  // ---------------------------------------------------------------------------

  void _onHostChanged() {
    final match = _revealWhenReady;
    if (match == null || !host.isReady) return;
    _revealWhenReady = null;
    host.changes.removeListener(_onHostChanged);
    // After the editor's own first layout (which frames the first page).
    scheduleMicrotask(() {
      if (!_disposed && currentMatch == match) _reveal(match);
    });
  }

  void _onGlyphs() {
    final match = _refineWhenLoaded;
    if (match != null && match == currentMatch && rectsOf(match).isNotEmpty) _reveal(match);
    notifyListeners(); // Highlights can be drawn now.
  }

  void _onSearchChanged() {
    if (_takeJump()) return;
    // PDF text was indexed: refresh the matches (unless a search typed is
    // due, which shows its first match too).
    if (_open && _query.isNotEmpty && !(_timer?.isActive ?? false)) {
      _timer?.cancel();
      _timer = Timer(_debounce, () {
        if (_disposed) return;
        _run();
        notifyListeners();
      });
    }
  }

  /// Shows a result the library asked for, if any. Returns whether it did.
  bool _takeJump() {
    final jump = search.takeJump(notebookId);
    if (jump == null) return false;
    _open = true;
    _query = jump.query;
    _timer?.cancel();
    _run();
    var index = _matches.indexWhere((m) => m.hit.refId == jump.hit.refId);
    if (index == -1 && _matches.isNotEmpty) index = 0;
    if (index != -1) {
      select(index);
    } else {
      notifyListeners();
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    search.removeListener(_onSearchChanged);
    glyphs
      ..removeListener(_onGlyphs)
      ..dispose();
    if (_revealWhenReady != null) host.changes.removeListener(_onHostChanged);
    super.dispose();
  }
}
