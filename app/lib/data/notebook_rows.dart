import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../domain/notebook.dart';
import '../domain/paper.dart';
import 'record_fields.dart';
import 'syncable.dart';

/// How a [Notebook] is stored: its row in `notebooks` and the data of its
/// sync record (`NotebookRepository`).
abstract final class NotebookRows {
  /// The notebook in [row].
  static Notebook fromRow(Row row) => Notebook(
    id: row['id'] as String,
    title: row['title'] as String,
    kind: NotebookKind.parse(row['kind'] as String),
    paper: _decodePaper(row['paper'] as String, row['paper_data'] as String),
    paperColor: PaperColor.parse(row['paper_color'] as String?),
    coverColor: row['cover_color'] as int,
    createdAt: row['created_at'] as int,
    updatedAt: row['updated_at'] as int,
    editedAt: row['edited_at'] as int,
    folderId: row['folder_id'] as String?,
    favorite: row['favorite'] == 1,
    trashedAt: row['trashed_at'] as int?,
  );

  /// The sync record data of a live notebook [row].
  static Map<String, Object?> recordData(Row row) => {
    'title': row['title'],
    'kind': row['kind'],
    'paper': row['paper'],
    'paperData': jsonDecode(row['paper_data'] as String),
    'paperColor': row['paper_color'],
    'coverColor': row['cover_color'],
    'createdAt': row['created_at'],
    'editedAt': row['edited_at'],
    'folderId': row['folder_id'],
    'favorite': row['favorite'] == 1,
    'trashedAt': row['trashed_at'],
  };

  /// Parses a live record; throws [FormatException] when malformed.
  static Notebook fromRecord(SyncRecord record) {
    final f = RecordFields(record);
    final style = f.choice('paper', PaperStyle.values);
    if (style.needsParams) f.invalid('paper'); // A default without parameters.
    final paper = Paper.fromData(style, f.object('paperData')) ?? f.invalid('paperData');
    return Notebook(
      id: record.id,
      title: f.string('title'),
      kind: f.choice('kind', NotebookKind.values),
      paper: paper,
      paperColor: PaperColor.tryParse(f.string('paperColor')) ?? f.invalid('paperColor'),
      coverColor: f.integer('coverColor'),
      createdAt: f.integer('createdAt'),
      updatedAt: record.updatedAt,
      editedAt: f.integer('editedAt'),
      folderId: f.stringOrNull('folderId'),
      favorite: f.boolean('favorite'),
      trashedAt: f.integerOrNull('trashedAt'),
    );
  }

  /// A stored default paper; a style needing parameters, unknown or
  /// corrupt data reads as blank.
  static Paper _decodePaper(String name, String data) {
    final style = PaperStyle.parse(name);
    if (style.needsParams) return Paper.blank;
    try {
      final json = jsonDecode(data);
      if (json is Map<String, Object?>) {
        return Paper.fromData(style, json, requireLook: false) ?? Paper(style);
      }
    } on FormatException {
      // Corrupt local data: the style's standard look.
    }
    return Paper(style);
  }
}
