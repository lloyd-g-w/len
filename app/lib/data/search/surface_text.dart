import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_database.dart';
import 'search_schema.dart';

/// The text on a page or canvas, for reading it aloud: its text boxes and
/// recognised handwriting in reading order (top to bottom, then left to
/// right), then the text of the PDF page under it, if extracted.
///
/// Read from the search index (`search_docs`, `ink_text`), which triggers
/// keep current, so it is what was last stored: a text box being typed in
/// shows once its write lands.
class SurfaceText {
  const SurfaceText(this.database);

  final AppDatabase database;

  /// The text of surface [surfaceId], one line per text box or handwritten
  /// line, a blank line before the PDF text; '' when there is none.
  String of(String surfaceId) {
    final notes = database.select(
      '''
      SELECT body FROM (
        SELECT d.body AS body, e.y AS y, e.x AS x FROM search_docs d
        JOIN elements e ON e.id = d.ref_id
        WHERE d.kind = '${SearchSchema.text}' AND d.surface_id = ?1
        UNION ALL
        SELECT text, y, x FROM ink_text WHERE surface_id = ?1 AND text <> ''
      ) ORDER BY y, x''',
      [surfaceId],
    );
    final pdf = database.select(
      "SELECT body FROM search_docs WHERE kind = '${SearchSchema.pdf}' AND ref_id = ?",
      [surfaceId],
    );
    final parts = [
      if (notes.isNotEmpty) notes.map((r) => (r['body'] as String).trim()).join('\n'),
      for (final r in pdf) (r['body'] as String).trim(),
    ];
    return parts.where((p) => p.isNotEmpty).join('\n\n');
  }
}

/// [SurfaceText] read lazily and kept per surface until the database
/// commits again (an edit, undo, sync or recognition stored), which drops
/// it all and notifies: listeners read again only what they still show.
class SurfaceTextCache extends ChangeNotifier {
  SurfaceTextCache(this.source) {
    _commits = source.database.commits.listen((_) => _invalidate());
  }

  final SurfaceText source;
  late final StreamSubscription<void> _commits;
  final _texts = <String, String>{};

  /// How many surfaces were read from the database (tests).
  @visibleForTesting
  int reads = 0;

  /// The text of surface [surfaceId] (see [SurfaceText.of]).
  String of(String surfaceId) => _texts[surfaceId] ??= _read(surfaceId);

  String _read(String surfaceId) {
    reads++;
    return source.of(surfaceId);
  }

  void _invalidate() {
    if (_texts.isEmpty) return; // Nothing read since: nothing to update.
    _texts.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_commits.cancel());
    super.dispose();
  }
}
