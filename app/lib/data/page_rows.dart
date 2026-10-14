import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../domain/notebook_page.dart';
import '../domain/paper.dart';
import 'record_fields.dart';
import 'syncable.dart';

/// How a [NotebookPage] is stored: its row in `pages` and the data of its
/// sync record (`PageRepository`).
abstract final class PageRows {
  /// The sync record data of a live page [row].
  static Map<String, Object?> recordData(Row row) {
    final background = row['background'] as String?;
    return {
      'notebookId': row['notebook_id'],
      'sortKey': row['sort_key'],
      'width': row['width'],
      'height': row['height'],
      'paper': row['paper'],
      'paperData': jsonDecode(row['paper_data'] as String),
      'paperColor': row['paper_color'],
      'bookmarked': row['bookmarked'] == 1,
      'background': background == null ? null : jsonDecode(background),
    };
  }

  /// Parses a live record; throws [FormatException] when malformed.
  static NotebookPage fromRecord(SyncRecord record) {
    final f = RecordFields(record);
    final width = f.number('width');
    final height = f.number('height');
    if (width <= 0) f.invalid('width');
    if (height <= 0) f.invalid('height');
    final rawBackground = f.objectOrNull('background');
    final background = rawBackground == null ? null : PageBackground.fromJson(rawBackground);
    if (rawBackground != null && background == null) f.invalid('background');
    final paper =
        Paper.fromData(f.choice('paper', PaperStyle.values), f.object('paperData')) ??
        f.invalid('paperData');
    return NotebookPage(
      id: record.id,
      notebookId: f.string('notebookId'),
      sortKey: f.number('sortKey'),
      width: width,
      height: height,
      paper: paper,
      paperColor: PaperColor.tryParse(f.string('paperColor')) ?? f.invalid('paperColor'),
      bookmarked: f.boolean('bookmarked'),
      background: background,
    );
  }

  /// A stored page background; null when absent or corrupt.
  static PageBackground? decodeBackground(String? json) {
    if (json == null) return null;
    try {
      return PageBackground.fromJson(jsonDecode(json));
    } on FormatException {
      return null;
    }
  }

  static Paper _decodePaper(String style, String data) {
    try {
      final json = jsonDecode(data);
      if (json is Map<String, Object?>) {
        return Paper.fromData(PaperStyle.parse(style), json, requireLook: false) ?? Paper.blank;
      }
    } on FormatException {
      // Corrupt local data reads as blank paper.
    }
    return Paper.blank;
  }

  /// The page in [row].
  static NotebookPage fromRow(Row row) => NotebookPage(
    id: row['id'] as String,
    notebookId: row['notebook_id'] as String,
    sortKey: (row['sort_key'] as num).toDouble(),
    width: (row['width'] as num).toDouble(),
    height: (row['height'] as num).toDouble(),
    paper: _decodePaper(row['paper'] as String, row['paper_data'] as String),
    paperColor: PaperColor.parse(row['paper_color'] as String?),
    bookmarked: row['bookmarked'] == 1,
    background: decodeBackground(row['background'] as String?),
  );
}
