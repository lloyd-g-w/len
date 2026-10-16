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
    this.base,
    this.seq,
  }) : data = deleted ? null : data;

  /// Allowed collection names.
  static final collectionPattern = RegExp(r'^[a-z_]{1,32}$');

  /// Maximum length of [id] and [deviceId].
  static const maxIdLength = 64;

  /// Maximum nesting depth of [data] (the object itself is depth 1).
  /// Bounds the recursion of `jsonEncode`, which would otherwise overflow
  /// the stack on deeply nested payloads (on push, or worse, on every pull).
  static const maxDataDepth = 64;

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

  /// The version a deletion replaced (on a tombstone), or the version the
  /// deletion a copy undoes had replaced (on a live record a deletion
  /// conflict brought back); `null` for none. Opaque to the server, which
  /// stores and returns it with the record (docs/SYNC_PROTOCOL.md,
  /// "Deletion conflicts").
  final RecordVersion? base;

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
      throw RecordValidationException('collection must match ${collectionPattern.pattern}');
    }
    final deleted = json['deleted'];
    if (deleted is! bool) {
      throw RecordValidationException('deleted must be a boolean');
    }
    final data = json['data'];
    if (data != null && data is! Map<String, Object?>) {
      throw RecordValidationException('data must be an object or null');
    }
    if (!deleted && data != null) _checkData(data);
    return SyncRecord(
      collection: collection,
      id: _requireId(json, 'id'),
      updatedAt: _requireInt(json, 'updatedAt'),
      deviceId: _requireId(json, 'deviceId'),
      deleted: deleted,
      data: data as Map<String, Object?>?,
      base: _optionalVersion(json, 'base'),
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
    if (base case final base?) 'base': base.toJson(),
    if (seq != null) 'seq': seq,
  };

  /// Parses the optional version [key] (`{"updatedAt": int, "deviceId": id}`
  /// or null).
  static RecordVersion? _optionalVersion(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! Map<String, Object?>) {
      throw RecordValidationException('$key must be an object or null');
    }
    try {
      return RecordVersion(
        updatedAt: _requireInt(value, 'updatedAt'),
        deviceId: _requireId(value, 'deviceId'),
      );
    } on RecordValidationException catch (e) {
      throw RecordValidationException('$key.${e.message}');
    }
  }

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
      throw RecordValidationException('$key must be 1..$maxIdLength characters long');
    }
    return value;
  }

  /// Rejects data nesting maps/lists deeper than [maxDataDepth], or holding
  /// numbers JSON cannot represent (`1e400` decodes to infinity, which could
  /// not be stored). Iterative, so arbitrarily deep input cannot overflow
  /// the stack.
  static void _checkData(Object value) {
    final stack = <(Object?, int)>[(value, 1)];
    while (stack.isNotEmpty) {
      final (node, depth) = stack.removeLast();
      final Iterable<Object?> children;
      if (node is Map) {
        children = node.values;
      } else if (node is List) {
        children = node;
      } else {
        continue;
      }
      if (depth > maxDataDepth) {
        throw RecordValidationException('data must not be nested deeper than $maxDataDepth levels');
      }
      for (final child in children) {
        if (child is Map || child is List) {
          stack.add((child, depth + 1));
        } else if (child is double && !child.isFinite) {
          throw RecordValidationException('data must not contain non-finite numbers');
        }
      }
    }
  }

  static int _requireInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! int) {
      throw RecordValidationException('$key must be an integer');
    }
    return value;
  }
}

/// A record version: `updatedAt` and `deviceId`.
class RecordVersion {
  const RecordVersion({required this.updatedAt, required this.deviceId});

  final int updatedAt;
  final String deviceId;

  Map<String, Object?> toJson() => {'updatedAt': updatedAt, 'deviceId': deviceId};
}
