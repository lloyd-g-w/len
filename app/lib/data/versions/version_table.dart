import 'dart:typed_data';

import '../../domain/notebook_version.dart';
import 'canonical_json.dart';
import 'version_packs.dart';

/// The table blobs of version history (docs/SYNC_PROTOCOL.md, "Version
/// history"): a version's body as rows (its canvas or pages, recordings and
/// outline entries), cut where a row's id hashes to a boundary so the rows
/// a version shares with the one before make the same blobs. A table blob
/// is a *reference blob* (`LR`, 1, deflated canonical JSON): blob garbage
/// collection, on the server too, follows the blobs it names.
abstract final class VersionTable {
  /// The blob type of a table blob.
  static const mime = 'application/x-len-table';

  /// The magic and format of reference blobs (docs/SYNC_PROTOCOL.md,
  /// "Reference blobs").
  static const magic = [0x4C, 0x52];
  static const format = 1;

  /// The rows of [body]: the canvas (id [notebookId]) or the pages in
  /// order, then the recordings and outline entries (in their order).
  static List<Map<String, Object?>> rowsOf(VersionBody body, String notebookId) => [
    if (body.canvas case final canvas?) {'t': 'canvas', 'id': notebookId, ...canvas.toJson()},
    for (final p in body.pages) {'t': 'page', 'id': p.id, ...p.fields, ...p.content.toJson()},
    for (final r in body.recordings ?? const <VersionRecord>[])
      {'t': 'recording', 'id': r.id, 'data': r.data},
    for (final e in body.outline ?? const <VersionRecord>[])
      {'t': 'outline', 'id': e.id, 'data': e.data},
  ];

  /// [rows] cut into the runs of one blob each.
  static List<List<Map<String, Object?>>> cut(List<Map<String, Object?>> rows) =>
      VersionPacks.cutBy(rows, (row) => row['id']! as String);

  /// The bytes of a table blob of [rows].
  static Uint8List encode(List<Map<String, Object?>> rows) =>
      DeflatedJson.encode(magic, format, rows);

  /// The rows of table blob [bytes]; null when they are none.
  static List<Map<String, Object?>>? decode(Uint8List bytes) {
    if (!DeflatedJson.isOf(bytes, magic, format)) return null;
    final rows = DeflatedJson.decode(bytes);
    if (rows is! List<Object?> || rows.any((row) => row is! Map<String, Object?>)) return null;
    return rows.cast<Map<String, Object?>>();
  }
}
