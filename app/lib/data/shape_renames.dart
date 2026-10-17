import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../domain/shape_ids.dart';

/// Renames the shapes of copied strokes in place ([ShapeIds]): their
/// origins and the targets of their connectors.
abstract final class ShapeRenames {
  /// Maps the shape names in the `style` of the stroke rows of [table] (a
  /// trusted constant: `strokes` or a temporary copy of its rows) on
  /// surface [surfaceId] (every row, when null) by [idOf].
  static void apply(
    CommonDatabase db,
    String Function(String old) idOf, {
    String table = 'strokes',
    String? surfaceId,
  }) {
    final rows = db.select(
      'SELECT id, style FROM $table WHERE style LIKE \'%"sh"%\''
      '${surfaceId == null ? '' : ' AND surface_id = ?'}',
      [?surfaceId],
    );
    for (final row in rows) {
      final style = row['style'] as String;
      if (!ShapeIds.mayName(style)) continue;
      final renamed = ShapeIds.remapStyle(jsonDecode(style), idOf);
      if (renamed == null) continue;
      db.execute('UPDATE $table SET style = ? WHERE id = ?', [jsonEncode(renamed), row['id']]);
    }
  }
}
