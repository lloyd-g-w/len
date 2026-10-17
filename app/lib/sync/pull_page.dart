import 'dart:convert';
import 'dart:typed_data';

import '../data/stroke_row.dart';
import '../data/syncable.dart';

/// One page of the server's change feed.
class PullPage {
  const PullPage({
    required this.records,
    required this.nextSince,
    required this.hasMore,
    required this.lastSeq,
    this.malformed = 0,
  });

  final List<SyncRecord> records;
  final int nextSince;
  final bool hasMore;

  /// The server's newest seq when it read the page (≥ [nextSince]): how
  /// far the feed goes, for showing progress.
  final int lastSeq;

  /// Records on this page that could not be parsed and were dropped.
  final int malformed;
}

/// Decodes a `/v1/pull` answer [body] (UTF-8 JSON) to a request after
/// [since]; null when it is not a valid page.
///
/// Malformed records are dropped (and counted) rather than failing the
/// whole page, so one bad record can never block sync forever. Live stroke
/// records are also parsed into their rows ([SyncRecord.prepared]; their
/// bulky payload is dropped), so the UI thread only writes them; one that
/// fails here is left to the store, which skips it. Pure, so it can run in
/// a worker isolate.
PullPage? decodePullPage(Uint8List body, {required int since}) {
  final Object? decoded;
  try {
    decoded = utf8.decoder.fuse(json.decoder).convert(body);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  final rawRecords = decoded['records'];
  final nextSince = decoded['nextSince'];
  final hasMore = decoded['hasMore'];
  final lastSeq = decoded['lastSeq'];
  if (rawRecords is! List ||
      nextSince is! int ||
      hasMore is! bool ||
      lastSeq is! int ||
      lastSeq < nextSince ||
      nextSince < since ||
      (hasMore && nextSince == since)) {
    return null;
  }
  final records = <SyncRecord>[];
  var malformed = 0;
  for (final raw in rawRecords) {
    final SyncRecord record;
    try {
      record = SyncRecord.fromJson(raw);
    } on FormatException {
      malformed++;
      continue;
    }
    records.add(prepareRecord(record));
  }
  return PullPage(
    records: records,
    nextSince: nextSince,
    hasMore: hasMore,
    lastSeq: lastSeq,
    malformed: malformed,
  );
}

/// [record], a live stroke parsed into its row ([SyncRecord.prepared];
/// its bulky payload dropped), so applying it only writes.
SyncRecord prepareRecord(SyncRecord record) {
  if (record.deleted || record.collection != 'strokes') return record;
  try {
    final row = StrokeRow.fromRecord(record.id, record.data!);
    return SyncRecord(
      collection: record.collection,
      id: record.id,
      updatedAt: record.updatedAt,
      deviceId: record.deviceId,
      deleted: false,
      data: {'surfaceId': row.surfaceId},
      prepared: row,
    );
  } on Object {
    return record; // Malformed: the store reports and skips it.
  }
}
