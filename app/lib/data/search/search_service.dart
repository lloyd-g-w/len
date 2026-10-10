import 'package:flutter/foundation.dart';

import '../app_database.dart';
import 'pdf_text_indexer.dart';
import 'pdf_text_source.dart';
import 'search_index.dart';
import 'search_query.dart';

/// A request to show a search result in a notebook's editor: made by the
/// library before opening the notebook, taken by the editor's search.
class SearchJump {
  const SearchJump({required this.notebookId, required this.query, required this.hit});

  final String notebookId;

  /// The text searched for (shown in the editor's search bar).
  final String query;

  /// The result to reveal and highlight.
  final SearchHit hit;
}

/// Full-text search for the app: the index, PDF text extraction, and
/// "open this result" requests. Notifies when indexed content changed in
/// the background (PDF text arrived) or a jump was requested.
class SearchService extends ChangeNotifier {
  SearchService(
    AppDatabase database, {
    required Future<Uint8List?> Function(String sha) readBlob,
    PdfTextSource pdfSource = const PdfrxTextSource(),
  }) : index = SearchIndex(database),
       pdfText = PdfTextIndexer(database, readBlob: readBlob, source: pdfSource) {
    pdfText.addListener(notifyListeners);
  }

  final SearchIndex index;
  final PdfTextIndexer pdfText;

  SearchJump? _pendingJump;

  /// Content and title hits for [query] (see [SearchIndex.search]). Also
  /// starts extracting text from PDFs not indexed yet; results grow as it
  /// progresses (listen to this service).
  List<SearchHit> search(String query, {String? notebookId}) {
    final parsed = SearchQuery(query);
    if (parsed.isEmpty) return const [];
    indexPdfs();
    return index.search(parsed, notebookId: notebookId);
  }

  /// Extracts text from any PDF pages not indexed yet, in the background.
  Future<void> indexPdfs({bool retryFailed = false}) => pdfText.schedule(retryFailed: retryFailed);

  /// Tells listeners that indexed content changed in the background
  /// (e.g. handwriting was recognised), so open results refresh.
  void contentChanged() => notifyListeners();

  /// Asks the editor of [SearchJump.notebookId] to show [jump] (it may not
  /// be open yet).
  void requestJump(SearchJump jump) {
    _pendingJump = jump;
    notifyListeners();
  }

  /// Takes the pending jump for [notebookId], if there is one.
  SearchJump? takeJump(String notebookId) {
    final jump = _pendingJump;
    if (jump == null || jump.notebookId != notebookId) return null;
    _pendingJump = null;
    return jump;
  }

  @override
  void dispose() {
    pdfText
      ..removeListener(notifyListeners)
      ..dispose();
    super.dispose();
  }
}
