/// A versioned record exchanged with the sync server.
/// See docs/SYNC_PROTOCOL.md.
class SyncRecord {
  const SyncRecord({
    required this.collection,
    required this.id,
    required this.updatedAt,
    required this.deviceId,
    required this.deleted,
    required this.data,
    this.prepared,
  });

  final String collection;
  final String id;
  final int updatedAt;
  final String deviceId;
  final bool deleted;

  /// Collection-specific payload; null for tombstones.
  final Map<String, Object?>? data;

  /// The record already parsed into what its store writes (a `StrokeRow`),
  /// done while decoding a pulled page; null when not. [data] then holds
  /// only what the sync engine reads itself (`surfaceId`).
  final Object? prepared;

  /// Whether this record should replace a local row with the given version
  /// under the last-write-wins rule.
  bool supersedes({required int updatedAt, required String deviceId}) {
    if (this.updatedAt != updatedAt) return this.updatedAt > updatedAt;
    return this.deviceId.compareTo(deviceId) > 0;
  }

  Map<String, Object?> toJson() => {
    'collection': collection,
    'id': id,
    'updatedAt': updatedAt,
    'deviceId': deviceId,
    'deleted': deleted,
    'data': deleted ? null : data,
  };

  /// Parses a server record; throws [FormatException] when malformed.
  ///
  /// Live records must carry a `data` object; tombstones drop any payload.
  factory SyncRecord.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('Record is not an object');
    }
    final collection = json['collection'];
    final id = json['id'];
    final updatedAt = json['updatedAt'];
    final deviceId = json['deviceId'];
    final deleted = json['deleted'];
    final data = json['data'];
    if (collection is! String ||
        id is! String ||
        updatedAt is! int ||
        deviceId is! String ||
        deleted is! bool ||
        id.isEmpty ||
        (!deleted && data is! Map<String, Object?>)) {
      // Do not echo the record: it may hold megabytes of point data.
      throw FormatException(
        'Malformed record ${collection is String ? collection : '?'}/'
        '${id is String ? id : '?'}',
      );
    }
    return SyncRecord(
      collection: collection,
      id: id,
      updatedAt: updatedAt,
      deviceId: deviceId,
      deleted: deleted,
      data: deleted ? null : data as Map<String, Object?>,
    );
  }
}

/// Identifies the exact local version of a row that was pushed, so it is
/// only marked clean if it has not been modified again in the meantime.
typedef RowVersion = ({String id, int updatedAt});

/// A local table that participates in sync.
abstract interface class SyncableStore {
  /// The protocol collection name, e.g. `strokes`.
  String get collection;

  /// Up to [limit] rows with unpushed local changes, ordered by id and
  /// starting after id [after] (keyset pagination, so rows that stay dirty
  /// cannot make a push loop spin on the same page). [deleted] limits them
  /// to tombstones (true) or live rows (false).
  List<SyncRecord> dirtyRecords(int limit, {String? after, bool? deleted});

  /// Clears the dirty flag of rows still at the given versions.
  void markClean(List<RowVersion> versions);

  /// Applies a remote record if it wins under last-write-wins.
  /// Returns true if local state changed.
  bool applyRemote(SyncRecord record);

  /// Flags every row as dirty, e.g. after switching to a new server.
  void markAllDirty();
}
