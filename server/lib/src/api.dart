/// HTTP API (routes, handlers and auth middleware) of the sync protocol v1.
library;

import 'dart:convert';
import 'dart:io' show HttpStatus, stderr;
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'blob_api.dart';
import 'blob_store.dart';
import 'change_events.dart';
import 'cors.dart';
import 'record.dart';
import 'record_store.dart';

/// Protocol version reported by `/v1/health`.
const protocolVersion = 1;

/// Maximum number of records per push.
const maxPushRecords = 1000;

/// Maximum push body size in bytes (32 MiB).
const maxPushBytes = 32 * 1024 * 1024;

/// Default and maximum page size for pull.
const defaultPullLimit = 500;
const maxPullLimit = 1000;

/// Paths reachable without a bearer token.
const _publicPaths = {'v1/health'};

/// Builds the complete request handler: CORS middleware ([cors], outermost,
/// so preflights and auth errors are covered), then auth, then the protocol
/// routes. Logging is left to the caller.
///
/// Blob uploads are limited to [maxBlobBytes]; the push body limit
/// ([maxPushBytes]) does not apply to them, and an upload pausing longer
/// than [blobIdleTimeout] is abandoned.
///
/// `GET /v1/events` streams through [events] (a new set if not given; the
/// caller closes it at shutdown).
Handler buildHandler({
  required RecordStore store,
  required BlobStore blobs,
  required String token,
  int maxBlobBytes = defaultMaxBlobBytes,
  Duration blobIdleTimeout = defaultBlobIdleTimeout,
  CorsPolicy cors = const CorsPolicy.any(),
  ChangeEvents? events,
}) {
  final changes = events ?? ChangeEvents();
  final router = Router(notFoundHandler: _notFound)
    ..get('/v1/health', (Request request) => _health(store, maxBlobBytes))
    ..post('/v1/push', (Request request) => _push(request, store, changes))
    ..get('/v1/pull', (Request request) => _pull(request, store, changes))
    ..get(
      '/v1/events',
      (Request request) => changes.subscribe(seq: store.currentSeq(), serverId: store.serverId),
    );
  addBlobRoutes(router, blobs, maxBytes: maxBlobBytes, idleTimeout: blobIdleTimeout);
  return const Pipeline()
      .addMiddleware(corsMiddleware(cors))
      .addMiddleware(_internalErrors)
      .addMiddleware(bearerAuth(token, publicPaths: _publicPaths))
      .addHandler(router.call);
}

/// Turns unexpected exceptions into a JSON 500 (inside the CORS middleware,
/// so browsers can read it); details go to stderr, never to the client.
///
/// A request whose body breaks off (the client hung up, or its connection
/// dropped, mid-request) is no server error: it is logged in one line and
/// answered 400, which nobody may be listening for any more.
Handler _internalErrors(Handler inner) {
  return (Request request) async {
    try {
      return await inner(request.change(body: _abortable(request.read())));
    } on HijackException {
      rethrow;
    } on _ClientAborted catch (e) {
      stderr.writeln('len-sync: ${request.method} /${request.url.path} broken off: ${e.cause}');
      return _json(HttpStatus.badRequest, {'error': 'request broken off'});
    } catch (e, st) {
      stderr.writeln('len-sync: error handling ${request.method} /${request.url.path}: $e\n$st');
      return _json(HttpStatus.internalServerError, {'error': 'internal server error'});
    }
  };
}

/// Thrown while reading a request body that broke off: the client hung up
/// or its connection dropped mid-request.
class _ClientAborted implements Exception {
  _ClientAborted(this.cause);

  /// What reading the body failed with.
  final Object cause;

  @override
  String toString() => 'client aborted: $cause';
}

/// [body], failing with [_ClientAborted] where reading it fails.
Stream<List<int>> _abortable(Stream<List<int>> body) =>
    body.handleError((Object e) => throw _ClientAborted(e), test: (e) => e is! _ClientAborted);

/// Middleware rejecting requests without `Authorization: Bearer <token>`
/// with 401, except for [publicPaths] (relative URL paths, no leading `/`).
Middleware bearerAuth(String token, {Set<String> publicPaths = const {}}) {
  final expected = utf8.encode(token);
  return (Handler inner) {
    return (Request request) {
      if (publicPaths.contains(request.url.path)) return inner(request);
      final presented = _bearerToken(request.headers['authorization']);
      if (presented == null || !constantTimeEquals(utf8.encode(presented), expected)) {
        return _json(HttpStatus.unauthorized, {'error': 'unauthorized'});
      }
      return inner(request);
    };
  };
}

/// Compares two byte sequences in time depending only on their lengths,
/// not on where they first differ.
bool constantTimeEquals(List<int> a, List<int> b) {
  var diff = a.length ^ b.length;
  final n = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    diff |= x ^ y;
  }
  return diff == 0;
}

/// Extracts the token from a `Bearer <token>` header value.
String? _bearerToken(String? header) {
  if (header == null) return null;
  const scheme = 'bearer ';
  if (header.length <= scheme.length ||
      header.substring(0, scheme.length).toLowerCase() != scheme) {
    return null;
  }
  return header.substring(scheme.length).trim();
}

/// `GET /v1/health`: liveness plus what clients need to know up front.
Response _health(RecordStore store, int maxBlobBytes) => _json(HttpStatus.ok, {
  'status': 'ok',
  'protocol': protocolVersion,
  'maxBlobBytes': maxBlobBytes,
  'blobsCollectedAt': store.blobsCollectedAt,
  'serverId': store.serverId,
});

Response _notFound(Request request) => _json(HttpStatus.notFound, {'error': 'not found'});

/// `POST /v1/push`: validates every record, then applies all atomically.
Future<Response> _push(Request request, RecordStore store, ChangeEvents events) async {
  final Object? body;
  try {
    body = await _readJsonBody(request, maxPushBytes);
  } on _TooLarge {
    return _tooLarge('body exceeds $maxPushBytes bytes');
  } on FormatException {
    return _badRequest('body must be valid UTF-8 JSON');
  }

  if (body is! Map<String, Object?>) {
    return _badRequest('body must be a JSON object');
  }
  final rawRecords = body['records'];
  if (rawRecords is! List<Object?>) {
    return _badRequest('records must be an array');
  }
  final since = body['since'] ?? 0;
  if (since is! int || since < 0) {
    return _badRequest('since must be a non-negative integer');
  }
  if (rawRecords.length > maxPushRecords) {
    return _tooLarge('at most $maxPushRecords records per push');
  }

  final records = <SyncRecord>[];
  for (var i = 0; i < rawRecords.length; i++) {
    try {
      records.add(SyncRecord.fromJson(rawRecords[i]));
    } on RecordValidationException catch (e) {
      // `index` lets the client skip just this record and push the rest.
      return _json(HttpStatus.badRequest, {'error': 'records[$i]: ${e.message}', 'index': i});
    }
  }

  final PushResult result;
  try {
    result = store.push(records, since: since);
  } on HistoryLostException {
    return _historyLost(store, events);
  }
  if (result.applied > 0) events.publish(seq: result.serverSeq, serverId: store.serverId);
  return _json(HttpStatus.ok, {
    'applied': result.applied,
    'ignored': result.ignored,
    'serverSeq': result.serverSeq,
  });
}

/// `GET /v1/pull?since=&limit=`: one page of the change feed.
Response _pull(Request request, RecordStore store, ChangeEvents events) {
  final params = request.url.queryParameters;
  final since = _intParam(params['since'], fallback: 0);
  final limit = _intParam(params['limit'], fallback: defaultPullLimit);
  if (since == null || since < 0) {
    return _badRequest('since must be a non-negative integer');
  }
  if (limit == null || limit < 1) {
    return _badRequest('limit must be a positive integer');
  }

  final PullResult page;
  try {
    page = store.pull(since: since, limit: limit > maxPullLimit ? maxPullLimit : limit);
  } on HistoryLostException {
    return _historyLost(store, events);
  }
  return _json(HttpStatus.ok, {
    'records': [for (final r in page.records) r.toJson()],
    'nextSince': page.nextSince,
    'hasMore': page.hasMore,
    'lastSeq': page.lastSeq,
  });
}

/// Parses an optional integer query parameter; `null` means invalid.
/// Only plain decimal digits are accepted (no sign, whitespace or `0x`).
int? _intParam(String? raw, {required int fallback}) =>
    raw == null ? fallback : (_digits.hasMatch(raw) ? int.tryParse(raw) : null);

final _digits = RegExp(r'^[0-9]{1,19}$');

/// Signals that a request body exceeded the allowed size.
class _TooLarge implements Exception {}

/// Reads and decodes the request body as JSON, enforcing [maxBytes] both via
/// `Content-Length` and while streaming.
///
/// Throws [_TooLarge] or [FormatException].
Future<Object?> _readJsonBody(Request request, int maxBytes) async {
  final declared = request.contentLength;
  if (declared != null && declared > maxBytes) throw _TooLarge();

  final builder = BytesBuilder(copy: false);
  await for (final chunk in request.read()) {
    builder.add(chunk);
    if (builder.length > maxBytes) throw _TooLarge();
  }
  final text = utf8.decode(builder.takeBytes());
  return jsonDecode(text);
}

/// 409: the client has seen changes this server no longer has. The server
/// took a new id: open event streams hear of it, so every client resets.
Response _historyLost(RecordStore store, ChangeEvents events) {
  events.publish(seq: store.currentSeq(), serverId: store.serverId);
  return _json(HttpStatus.conflict, {
    'error': 'history lost: the server was restored or replaced; upload everything again',
  });
}

Response _badRequest(String message) => _json(HttpStatus.badRequest, {'error': message});

Response _tooLarge(String message) => _json(HttpStatus.requestEntityTooLarge, {'error': message});

Response _json(int status, Object body) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json; charset=utf-8'},
);
