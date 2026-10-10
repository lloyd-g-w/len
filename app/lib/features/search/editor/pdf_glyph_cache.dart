import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/search/pdf_text_source.dart';

/// Loads, on demand, where each character of a PDF page is, to highlight
/// matches in PDF text. Notifies when a requested page has loaded.
///
/// Keeps the most recently used PDF open and an LRU of pages.
class PdfGlyphCache extends ChangeNotifier {
  PdfGlyphCache({
    required this.readBlob,
    this.source = const PdfrxTextSource(),
    this.capacity = 24,
  });

  /// The bytes of a blob (fetching it if needed), or null.
  final Future<Uint8List?> Function(String sha) readBlob;
  final PdfTextSource source;

  /// Pages kept.
  final int capacity;

  final Map<(String, int), PdfGlyphs?> _pages = {};
  final Set<(String, int)> _loading = {};
  String? _openBlob;
  Future<PdfTextDocument?>? _openDoc;
  Future<void> _queue = Future.value();
  bool _disposed = false;

  /// Glyphs of page [page] of PDF [blob]; null until loaded (a load is
  /// started) or if the page has no usable glyphs.
  PdfGlyphs? glyphs(String blob, int page) {
    final key = (blob, page);
    if (_pages.containsKey(key)) {
      final value = _pages.remove(key);
      return _pages[key] = value; // Most recently used.
    }
    if (_loading.add(key)) _queue = _queue.then((_) => _load(key));
    return null;
  }

  Future<void> _load((String, int) key) async {
    if (_disposed) return;
    final (blob, page) = key;
    PdfGlyphs? result;
    try {
      final doc = await _document(blob);
      if (doc != null && page < doc.pageCount) result = await doc.glyphs(page);
    } on Object catch (e) {
      debugPrint('Cannot read glyphs of $blob p$page: $e');
    }
    if (_disposed) return;
    _loading.remove(key);
    _pages[key] = result;
    while (_pages.length > capacity) {
      _pages.remove(_pages.keys.first);
    }
    notifyListeners();
  }

  Future<PdfTextDocument?> _document(String blob) {
    if (_openBlob == blob && _openDoc != null) return _openDoc!;
    final previous = _openDoc;
    _openBlob = blob;
    late final Future<PdfTextDocument?> opening;
    opening = () async {
      try {
        await (await previous)?.dispose();
      } on Object {
        // It never opened.
      }
      try {
        final bytes = await readBlob(blob);
        final doc = bytes == null ? null : await source.open(bytes);
        if (doc == null) _forget(opening); // Not here yet: try again later.
        return doc;
      } on Object {
        _forget(opening);
        rethrow;
      }
    }();
    return _openDoc = opening;
  }

  /// Drops a failed [opening] so the next request opens the blob again.
  void _forget(Future<PdfTextDocument?> opening) {
    if (identical(_openDoc, opening)) {
      _openDoc = null;
      _openBlob = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final doc = _openDoc;
    unawaited(_queue.then((_) async => (await doc)?.dispose()).catchError((Object _) {}));
    super.dispose();
  }
}
