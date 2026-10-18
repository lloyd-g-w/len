import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../../domain/notebook_version.dart';
import '../blob_references.dart';
import '../blob_store.dart';
import '../repositories.dart';
import '../syncable_table.dart';
import 'pack_runs.dart';
import 'pending_blobs.dart';
import 'version_packs.dart';
import 'work_slices.dart';

/// A surface packed: its packs, the blobs its elements show and how many
/// strokes it holds.
typedef PackedSurface = ({VersionSurface surface, List<String> blobs, int strokes});

/// Packs surfaces for versions (docs/ARCHITECTURE.md, "Version history"):
/// a surface's packs come from the `version_packs` cache while its change
/// mark holds; otherwise its strokes are listed (ids only) and cut, and only
/// runs not packed before ([PackRuns]) are read whole and encoded, a run
/// per slice of [WorkSlices].
class SurfacePacker {
  SurfacePacker({required this.repositories, required this.blobs})
    : _runs = PackRuns(repositories.versions.db, blobs);

  final Repositories repositories;
  final BlobStore blobs;
  final PackRuns _runs;

  CommonDatabase get _db => repositories.versions.db;

  /// The packs of surface [surfaceId] as stored now (from the cache while
  /// its change mark holds and its packs are still here). Long work yields
  /// through [slices].
  Future<PackedSurface> pack(String surfaceId, [WorkSlices? slices]) async {
    slices ??= WorkSlices();
    while (true) {
      final packed = await _tryPack(surfaceId, slices);
      if (packed != null) return packed;
    }
  }

  /// Null when the surface changed while it was read (pack again).
  Future<PackedSurface?> _tryPack(String surfaceId, WorkSlices slices) async {
    await slices.yieldIfDue();
    // The elements are read with the mark (no await between); the strokes'
    // ids in slices after it, the strokes themselves run by run (a stroke
    // never changes under its id). If the mark moved meanwhile, or a
    // stroke listed is gone, the surface is packed again, so the packs are
    // those of the state the mark names. An edit written in steps
    // ([AppDatabase.steps]) finishes before the mark is read (both times):
    // a version never holds half of it.
    final mark = _markOf(surfaceId);
    if (_cached(surfaceId, mark) case final packed?) return packed;
    final items = _elements(surfaceId);
    final media = <String>{for (final (_, data) in items) ...BlobReferences.inValue(data)};
    final ink = await _strokeIds(surfaceId, slices);
    final inkPacks = <String>[];
    for (final run in VersionPacks.cutBy(ink, (id) => id)) {
      await slices.yieldIfDue();
      final key = PackRuns.strokesKey(run);
      if (_runs.find(key) case final sha?) {
        inkPacks.add(sha);
        continue;
      }
      final strokes = _strokes(run);
      if (strokes == null) return null;
      inkPacks.add(await _runs.put(key, strokes));
    }
    final itemPacks = <String>[];
    for (final run in VersionPacks.cut(items)) {
      await slices.yieldIfDue();
      final key = PackRuns.elementsKey([for (final (id, data) in run) '$id@${data['_v']}']);
      itemPacks.add(
        _runs.find(key) ??
            await _runs.put(key, [
              for (final (id, data) in run) (id, {...data}..remove('_v')),
            ]),
      );
    }
    if (_markOf(surfaceId) != mark) return null;
    final surface = VersionSurface(ink: inkPacks, items: itemPacks);
    final packed = (surface: surface, blobs: media.toList()..sort(), strokes: ink.length);
    _db.execute(
      'INSERT OR REPLACE INTO version_packs (surface_id, mark, ink, items, blobs, strokes, size) '
      'VALUES (?, ?, ?, ?, ?, ?, 0)',
      [
        surfaceId,
        mark,
        jsonEncode(surface.ink),
        jsonEncode(surface.items),
        jsonEncode(packed.blobs),
        packed.strokes,
      ],
    );
    return packed;
  }

  /// [pack] in one turn (a restore's last try, docs/ARCHITECTURE.md,
  /// "Version history"): new packs go to [pending], stored after it.
  PackedSurface packNow(String surfaceId, PendingBlobs pending) {
    final mark = _markOf(surfaceId);
    if (_cached(surfaceId, mark) case final packed?) return packed;
    final items = _elements(surfaceId);
    final media = <String>{for (final (_, data) in items) ...BlobReferences.inValue(data)};
    final ink = [
      for (final row in _db.select(
        'SELECT id FROM strokes WHERE surface_id = ? AND deleted = 0 ORDER BY created_at, id',
        [surfaceId],
      ))
        row['id'] as String,
    ];
    final surface = VersionSurface(
      ink: [
        for (final run in VersionPacks.cutBy(ink, (id) => id))
          switch (PackRuns.strokesKey(run)) {
            final key => _runs.find(key) ?? _runs.putNow(key, _strokes(run)!, pending),
          },
      ],
      items: [
        for (final run in VersionPacks.cut(items))
          switch (PackRuns.elementsKey([for (final (id, data) in run) '$id@${data['_v']}'])) {
            final key =>
              _runs.find(key) ??
                  _runs.putNow(key, [
                    for (final (id, data) in run) (id, {...data}..remove('_v')),
                  ], pending),
          },
      ],
    );
    return (surface: surface, blobs: media.toList()..sort(), strokes: ink.length);
  }

  PackedSurface? _cached(String surfaceId, String mark) {
    final cached = _db.select('SELECT * FROM version_packs WHERE surface_id = ?', [surfaceId]);
    if (cached.isEmpty || cached.first['mark'] != mark) return null;
    final row = cached.first;
    final surface = VersionSurface(
      ink: _list(row['ink'] as String),
      items: _list(row['items'] as String),
    );
    if (!surface.packs.every(blobs.reuse)) return null;
    return (surface: surface, blobs: _list(row['blobs'] as String), strokes: row['strokes'] as int);
  }

  /// Every stroke or element written on [surfaceId] (tombstones too)
  /// changes it.
  String _markOf(String surfaceId) {
    repositories.versions.database.steps.finish();
    return _marks(surfaceId);
  }

  String _marks(String surfaceId) => [
    for (final table in const ['strokes', 'elements'])
      switch (_db.select(
        'SELECT COUNT(*) AS n, MAX(updated_at) AS v FROM $table WHERE surface_id = ?',
        [surfaceId],
      ).first) {
        final row => '${row['n']}:${row['v']}',
      },
  ].join('|');

  /// The ids of the live strokes on [surfaceId] in paint order
  /// (`createdAt`, id), read [idsPerRead] at a time.
  Future<List<String>> _strokeIds(String surfaceId, WorkSlices slices) async {
    final ids = <String>[];
    ({int createdAt, String id})? after;
    while (true) {
      final rows = _db.select(
        'SELECT id, created_at FROM strokes WHERE surface_id = ? AND deleted = 0 '
        '${after == null ? '' : 'AND (created_at, id) > (?, ?) '}'
        'ORDER BY created_at, id LIMIT $idsPerRead',
        [surfaceId, ?after?.createdAt, ?after?.id],
      );
      for (final row in rows) {
        ids.add(row['id'] as String);
      }
      if (rows.length < idsPerRead) return ids;
      after = (createdAt: rows.last['created_at'] as int, id: rows.last['id'] as String);
      await slices.yieldIfDue();
    }
  }

  /// How many strokes' ids one read lists (a few ms).
  static const idsPerRead = 2000;

  /// Strokes [ids] (in that order) as pack items; null when one is no
  /// longer live.
  List<PackItem>? _strokes(List<String> ids) {
    final marks = List.filled(ids.length, '?').join(', ');
    final rows = {
      for (final row in _db.select('SELECT * FROM strokes WHERE id IN ($marks)', ids))
        row['id'] as String: row,
    };
    final items = <PackItem>[];
    for (final id in ids) {
      final data = switch (rows[id]) {
        final row? => repositories.strokes.rowToRecord(row).data,
        null => null,
      };
      if (data == null) return null;
      items.add((id, {...data}..remove('surfaceId')));
    }
    return items;
  }

  /// The live elements on [surfaceId] in paint order, each with its
  /// version under `_v` (for its run's key).
  List<PackItem> _elements(String surfaceId) {
    final SyncableTable store = repositories.elements;
    final items = <PackItem>[
      for (final row in _db.select('SELECT * FROM elements WHERE surface_id = ? AND deleted = 0', [
        surfaceId,
      ]))
        (
          row['id'] as String,
          {...store.rowToRecord(row).data!, '_v': row['updated_at']}..remove('surfaceId'),
        ),
    ];
    items.sort((a, b) {
      final byTime = (a.$2['createdAt'] as int).compareTo(b.$2['createdAt'] as int);
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });
    return items;
  }

  static List<String> _list(String json) => (jsonDecode(json) as List).cast<String>();
}
