import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../domain/chunk_digest.dart';
import '../domain/surface_element.dart';
import '../domain/text/text_data.dart';
import 'stroke_queries.dart';

/// Points copied text boxes flowing across pages at the copies of the
/// boxes they continue (`TextFlow.from`), in place.
abstract final class TextFlowRelinks {
  /// Maps the flow of each live text box on surface [surfaceId] by
  /// [fromOf] (the box before's old id → the id it continues now; null:
  /// that box was not copied, and the box stands alone, its flow dropped),
  /// updating its chunk digests; with [only], just the boxes it names.
  /// Returns how many boxes changed.
  static int apply(
    CommonDatabase db,
    String surfaceId,
    String? Function(String from) fromOf, {
    Set<String>? only,
  }) {
    final rows = db.select(
      'SELECT id, data FROM elements WHERE surface_id = ? AND type = ? AND deleted = 0 '
      "AND data LIKE '%\"flow\"%'",
      [surfaceId, ElementType.text.name],
    );
    var changed = 0;
    for (final row in rows) {
      if (only != null && !only.contains(row['id'])) continue;
      final data = StrokeQueries.decodeElementData(row['data'] as String);
      if (data == null || data['flow'] == null) continue;
      final flow = TextFlow.fromJson(data['flow']);
      final from = flow == null ? null : fromOf(flow.from);
      if (from == flow?.from) continue;
      final next = {...data}..remove('flow');
      if (from != null) next['flow'] = flow!.withFrom(from).toJson();
      db.execute('UPDATE elements SET data = ? WHERE id = ?', [jsonEncode(next), row['id']]);
      changed++;
      final element = StrokeQueries.rowToElement(
        db.select('SELECT * FROM elements WHERE id = ?', [row['id']]).first,
      );
      if (element == null) continue;
      db.execute('UPDATE element_chunks SET digest = ? WHERE element_id = ?', [
        ChunkDigest.ofElement(element),
        row['id'],
      ]);
    }
    return changed;
  }
}
