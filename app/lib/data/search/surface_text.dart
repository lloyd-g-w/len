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
  /// line, a blank line before the PDF text; '' when there is none. Text
  /// boxes named in [except] are left out (they are read on their own).
  String of(String surfaceId, {Set<String> except = const {}}) =>
      read(surfaceId).join(except: except);

  /// The parts of surface [surfaceId]'s text (see [of]).
  SurfaceTextParts read(String surfaceId) {
    final notes = database.select(
      '''
      SELECT box, body FROM (
        SELECT e.id AS box, d.body AS body, e.y AS y, e.x AS x FROM search_docs d
        JOIN elements e ON e.id = d.ref_id
        WHERE d.kind = '${SearchSchema.text}' AND d.surface_id = ?1
        UNION ALL
        SELECT NULL, text, y, x FROM ink_text WHERE surface_id = ?1 AND text <> ''
      ) ORDER BY y, x''',
      [surfaceId],
    );
    final pdf = database.select(
      "SELECT body FROM search_docs WHERE kind = '${SearchSchema.pdf}' AND ref_id = ?",
      [surfaceId],
    );
    return SurfaceTextParts(
      notes: [
        for (final r in notes) (box: r['box'] as String?, text: (r['body'] as String).trim()),
      ],
      pdf: [for (final r in pdf) (r['body'] as String).trim()],
    );
  }
}

/// A surface's text as read: its notes (text boxes, named by [box], and
/// handwritten lines, unnamed) in reading order, then its PDF text.
@immutable
class SurfaceTextParts {
  const SurfaceTextParts({required this.notes, required this.pdf});

  final List<({String? box, String text})> notes;
  final List<String> pdf;

  /// One line per note but the text boxes in [except], a blank line before
  /// the PDF text.
  String join({Set<String> except = const {}}) {
    final lines = [
      for (final n in notes)
        if (n.box == null || !except.contains(n.box)) n.text,
    ];
    final parts = [if (lines.isNotEmpty) lines.join('\n'), ...pdf];
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
  final _texts = <String, SurfaceTextParts>{};

  /// How many surfaces were read from the database (tests).
  @visibleForTesting
  int reads = 0;

  /// The text of surface [surfaceId] but the text boxes in [except] (see
  /// [SurfaceText.of]).
  String of(String surfaceId, {Set<String> except = const {}}) =>
      (_texts[surfaceId] ??= _read(surfaceId)).join(except: except);

  SurfaceTextParts _read(String surfaceId) {
    reads++;
    return source.read(surfaceId);
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
