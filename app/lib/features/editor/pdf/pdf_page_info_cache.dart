import 'dart:async';

import 'package:flutter/foundation.dart';

import 'pdf_page_info.dart';

typedef _Page = (String blob, int page);

/// Text and links of the PDF pages an editor shows, loaded on demand and
/// kept (least recently used out); notifies when a requested page loaded.
class PdfPageInfoCache extends ChangeNotifier {
  PdfPageInfoCache(this.source, {this.capacity = 32});

  final PdfInfoSource source;

  /// Pages kept.
  final int capacity;

  final Map<_Page, ({PdfGlyphs? glyphs, List<PdfLinkArea> links})> _pages = {};
  final Set<_Page> _loading = {};
  final Map<String, Future<List<PdfOutlineItem>>> _outlines = {};
  bool _disposed = false;

  /// Bumped by [retry].
  int _generation = 0;

  /// Whether page [page] of [blob] has loaded (else a load is started).
  bool isLoaded(String blob, int page) => _entry(blob, page) != null;

  /// The text of page [page] of [blob]; null until loaded (a load is
  /// started) or when it has none.
  PdfGlyphs? glyphs(String blob, int page) => _entry(blob, page)?.glyphs;

  /// The links of page [page] of [blob]; empty until loaded.
  List<PdfLinkArea> links(String blob, int page) => _entry(blob, page)?.links ?? const [];

  /// Loads page [page] of [blob] (if needed) and completes when it is.
  Future<void> load(String blob, int page) async {
    if (_entry(blob, page) != null) return;
    await _load((blob, page));
  }

  /// Forgets pages without text or links, e.g. after a sync brought PDFs
  /// that were not on this device yet.
  void retry() {
    // Reads in flight may predate the PDF: their results are dropped and
    // the pages read again when next asked for.
    _generation++;
    _loading.clear();
    _pending.clear();
    _pages.removeWhere((_, v) => v.glyphs == null && v.links.isEmpty);
    _outlines.clear();
    notifyListeners();
  }

  /// The outline of PDF [blob].
  Future<List<PdfOutlineItem>> outline(String blob) =>
      _outlines[blob] ??= source.outline(blob).catchError((Object e) {
        debugPrint('Cannot read the outline of $blob: $e');
        _outlines.remove(blob); // Try again next time.
        return const <PdfOutlineItem>[];
      });

  ({PdfGlyphs? glyphs, List<PdfLinkArea> links})? _entry(String blob, int page) {
    final key = (blob, page);
    final hit = _pages.remove(key);
    if (hit != null) return _pages[key] = hit; // Most recently used.
    if (!_loading.contains(key)) unawaited(_load(key));
    return null;
  }

  final Map<_Page, Completer<void>> _pending = {};

  Future<void> _load(_Page key) {
    final pending = _pending[key];
    if (pending != null) return pending.future;
    final done = _pending[key] = Completer<void>();
    _loading.add(key);
    unawaited(_read(key).whenComplete(done.complete));
    return done.future;
  }

  Future<void> _read(_Page key) async {
    final (blob, page) = key;
    final generation = _generation;
    PdfGlyphs? glyphs;
    var links = const <PdfLinkArea>[];
    try {
      glyphs = await source.glyphs(blob, page);
      links = await source.links(blob, page);
    } on Object catch (e) {
      debugPrint('Cannot read text / links of $blob p$page: $e');
    }
    if (generation != _generation) return; // Retried meanwhile.
    _loading.remove(key);
    _pending.remove(key);
    if (_disposed) return;
    _pages[key] = (glyphs: glyphs, links: links);
    while (_pages.length > capacity) {
      _pages.remove(_pages.keys.first);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
