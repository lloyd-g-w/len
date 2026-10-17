/// Parsing a push (`POST /v1/push`, or a live connection's `push` message).
library;

import 'dart:io' show HttpStatus;

import 'record.dart';

/// Maximum number of records per push.
const maxPushRecords = 1000;

/// A push that cannot be applied: answered with [status] and [message]
/// (and [index], the invalid record's position).
class PushRejected implements Exception {
  const PushRejected(this.status, this.message, {this.index});

  final int status;
  final String message;
  final int? index;

  @override
  String toString() => 'PushRejected($status): $message';
}

/// A parsed push: the newest seq the client pulled and the records.
typedef PushRequest = ({int since, List<SyncRecord> records});

/// Parses and validates a push [body] (`{"since": …, "records": […]}`).
/// Throws [PushRejected].
PushRequest parsePush(Object? body) {
  if (body is! Map<String, Object?>) {
    throw const PushRejected(HttpStatus.badRequest, 'body must be a JSON object');
  }
  final rawRecords = body['records'];
  if (rawRecords is! List<Object?>) {
    throw const PushRejected(HttpStatus.badRequest, 'records must be an array');
  }
  final since = body['since'] ?? 0;
  if (since is! int || since < 0) {
    throw const PushRejected(HttpStatus.badRequest, 'since must be a non-negative integer');
  }
  if (rawRecords.length > maxPushRecords) {
    throw const PushRejected(
      HttpStatus.requestEntityTooLarge,
      'at most $maxPushRecords records per push',
    );
  }
  final records = <SyncRecord>[];
  for (var i = 0; i < rawRecords.length; i++) {
    try {
      records.add(SyncRecord.fromJson(rawRecords[i]));
    } on RecordValidationException catch (e) {
      // `index` lets the client skip just this record and push the rest.
      throw PushRejected(HttpStatus.badRequest, 'records[$i]: ${e.message}', index: i);
    }
  }
  return (since: since, records: records);
}
