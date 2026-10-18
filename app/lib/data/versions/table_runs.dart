import 'package:flutter/foundation.dart';

import '../blob_links.dart';
import '../blob_references.dart';
import '../blob_store.dart';
import 'pending_blobs.dart';
import 'version_table.dart';
import 'work_slices.dart';

/// Writes versions' table blobs (`VersionTable`), each run of rows once:
/// a run equal to one of the version made here before of the same notebook
/// takes that one's blob without encoding it again (a canvas row naming
/// 1,500 packs is ~100 KB of JSON to deflate). A large run is encoded on a
/// worker isolate where there are any (`compute`).
class TableRuns {
  TableRuns({required this.blobs, this.links});

  final BlobStore blobs;
  final BlobLinks? links;

  /// Per notebook, the runs of the version made here last and their blobs.
  final Map<String, List<(List<Map<String, Object?>>, String)>> _last = {};

  /// Notebooks whose last runs are kept.
  static const _kept = 4;

  /// Runs holding more values than this are encoded by `compute`.
  static const isolateValues = 500;

  /// Writes the table blobs of [rows] (of notebook [notebookId]), noting
  /// what each names; yields through [slices].
  Future<List<String>> put(
    String notebookId,
    List<Map<String, Object?>> rows,
    WorkSlices slices,
  ) async {
    final before = <Object?, (List<Map<String, Object?>>, String)>{
      for (final (run, sha)
          in _last.remove(notebookId) ?? const <(List<Map<String, Object?>>, String)>[])
        run.first['id']: (run, sha),
    };
    final made = <(List<Map<String, Object?>>, String)>[];
    for (final run in VersionTable.cut(rows)) {
      await slices.yieldIfDue();
      final old = before[run.first['id']];
      if (old != null && jsonEquals(old.$1, run) && blobs.reuse(old.$2)) {
        made.add((run, old.$2));
        continue;
      }
      final bytes = _values(run, isolateValues) > isolateValues
          ? await compute(VersionTable.encode, run)
          : VersionTable.encode(run);
      final sha = await blobs.putBytes(bytes, mime: VersionTable.mime);
      links?.add(sha, BlobReferences.inValue(run));
      made.add((run, sha));
    }
    _last[notebookId] = made;
    if (_last.length > _kept) _last.remove(_last.keys.first);
    return [for (final (_, sha) in made) sha];
  }

  /// [put] in one turn: new blobs go to [pending], stored after it.
  List<String> putNow(String notebookId, List<Map<String, Object?>> rows, PendingBlobs pending) {
    final before = <Object?, (List<Map<String, Object?>>, String)>{
      for (final (run, sha) in _last[notebookId] ?? const <(List<Map<String, Object?>>, String)>[])
        run.first['id']: (run, sha),
    };
    return [
      for (final run in VersionTable.cut(rows))
        switch (before[run.first['id']]) {
          final old? when jsonEquals(old.$1, run) && blobs.reuse(old.$2) => old.$2,
          _ => pending.put(
            VersionTable.encode(run),
            mime: VersionTable.mime,
            stored: (sha) => links?.add(sha, BlobReferences.inValue(run)),
          ),
        },
    ];
  }

  /// How many values [value] holds, counted up to [cap].
  static int _values(Object? value, int cap) {
    var n = 0;
    void walk(Object? v) {
      if (n > cap) return;
      n++;
      if (v is Map) {
        v.values.forEach(walk);
      } else if (v is List) {
        v.forEach(walk);
      }
    }

    walk(value);
    return n;
  }
}

/// Whether JSON values [a] and [b] are equal (maps by keys, lists in order).
bool jsonEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (!b.containsKey(e.key) || !jsonEquals(e.value, b[e.key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
