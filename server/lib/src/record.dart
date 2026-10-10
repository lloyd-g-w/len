/// The sync record model, its validation and JSON (de)serialization.
library;

/// Thrown when a JSON value does not describe a valid [SyncRecord].
class RecordValidationException implements Exception {
  RecordValidationException(this.message);

  final String message;

  @override
  String toString() => 'RecordValidationException: $message';
}

/// A generic last-write-wins record, as defined by the sync protocol v1.
class SyncRecord {
  SyncRecord({
    required this.collection,
    required this.id,
    required this.updatedAt,
    required this.deviceId,
    required this.deleted,
    required Map<String, Object?>? data,
    this.seq,
  }) : data = deleted ? null : data;

  /// Allowed collection names.
  static final collectionPattern = RegExp(r'^[a-z_]{1,32}$');

  /// Maximum length of [id] and [deviceId].
  static const maxIdLength = 64;

  final String collection;
  final String id;

  /// Client clock in milliseconds since epoch.
  final int updatedAt;

  /// Tie-breaker for equal [updatedAt].
  final String deviceId;

  /// Tombstone flag. Deleted records always have `null` [data].
  final bool deleted;

  /// Opaque JSON object payload.
  final Map<String, Object?>? data;

  /// Server-assigned change number; `null` for records not yet stored.
  final int? seq;

  /// Parses and strictly validates a record received from a client.
  ///
  /// Any `seq` sent by the client is ignored. If `deleted` is true the
  /// payload is dropped. Throws [RecordValidationException] on invalid input.
  factory SyncRecord.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw RecordValidationException('record must be a JSON object');
    }
    final collection = _requireString(json, 'collection');
    if (!collectionPattern.hasMatch(collection)) {
      throw RecordValidationException(
        'collection must match ${collectionPattern.pattern}',
      );
    }
    final deleted = json['deleted'];
    if (deleted is! bool) {
      throw RecordValidationException('deleted must be a boolean');
    }
    final data = json['data'];
    if (data != null && data is! Map<String, Object?>) {
      throw RecordValidationException('data must be an object or null');
    }
    return SyncRecord(
      collection: collection,
      id: _requireId(json, 'id'),
      updatedAt: _requireInt(json, 'updatedAt'),
      deviceId: _requireId(json, 'deviceId'),
      deleted: deleted,
      data: data as Map<String, Object?>?,
    );
  }

  /// Whether this record wins over [other] under the LWW rule, i.e.
  /// `(updatedAt, deviceId)` is lexicographically greater.
  bool beats({required int updatedAt, required String deviceId}) {
    if (this.updatedAt != updatedAt) return this.updatedAt > updatedAt;
    return this.deviceId.compareTo(deviceId) > 0;
  }

  /// JSON representation; includes `seq` when known.
  Map<String, Object?> toJson() => {
    'collection': collection,
    'id': id,
    'updatedAt': updatedAt,
    'deviceId': deviceId,
    'deleted': deleted,
    'data': data,
    if (seq != null) 'seq': seq,
  };

  static String _requireString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String) {
      throw RecordValidationException('$key must be a string');
    }
    return value;
  }

  static String _requireId(Map<String, Object?> json, String key) {
    final value = _requireString(json, key);
    if (value.isEmpty || value.length > maxIdLength) {
      throw RecordValidationException(
        '$key must be 1..$maxIdLength characters long',
      );
    }
    return value;
  }

  static int _requireInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! int) {
      throw RecordValidationException('$key must be an integer');
    }
    return value;
  }
}
