import 'app_database.dart';
import 'element_repository.dart';
import 'stroke_repository.dart';

/// How long tombstones keep what they deleted.
///
/// A deleted stroke or element keeps its points or data, and deleted pages,
/// elements and recordings keep their blobs, for [retention]: if the
/// deletion raced an edit on another device, sync brings the deleted
/// content back (docs/SYNC_PROTOCOL.md, "Deletion conflicts"). Afterwards
/// the payload is dropped and the blobs are left to garbage collection.
class TombstonePayloads {
  TombstonePayloads({required this.database, required this.strokes, required this.elements});

  final AppDatabase database;
  final StrokeRepository strokes;
  final ElementRepository elements;

  /// Matches the server's blob grace period, so a revived row finds its
  /// blobs there too.
  static const retention = Duration(days: 30);

  /// The oldest tombstone version (ms) that still keeps its payload at [nowMs].
  static int keptSince(int nowMs) => nowMs - retention.inMilliseconds;

  /// Drops the payloads of tombstones older than [retention], [batch] rows
  /// per transaction with a turn of the event loop between them (a deleted
  /// notebook's month-old tombstones can be 100,000 strokes).
  Future<void> purge(int nowMs) async {
    final before = keptSince(nowMs);
    for (final table in [strokes.purgeTombstones, elements.purgeTombstones]) {
      while (database.transaction(() => table(before, limit: batch)) == batch) {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  /// Rows purged per transaction (≈ 10 ms).
  static const batch = 2000;
}
