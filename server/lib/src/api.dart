/// HTTP API (routes, handlers and auth middleware) of the sync protocol v1.
library;

import 'dart:convert';
import 'dart:io' show HttpStatus;
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'blob_api.dart';
import 'blob_store.dart';
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

/// Builds the complete request handler: auth middleware in front of the
/// protocol routes. Logging is left to the caller.
///
/// Blob uploads are limited to [maxBlobBytes]; the push body limit
/// ([maxPushBytes]) does not apply to them.
Handler buildHandler({
  required RecordStore store,
  required BlobStore blobs,
  required String token,
  int maxBlobBytes = defaultMaxBlobBytes,
}) {
  final router = Router(notFoundHandler: _notFound)
    ..get('/v1/health', _health)
    ..post('/v1/push', (Request request) => _push(request, store))
    ..get('/v1/pull', (Request request) => _pull(request, store));
  addBlobRoutes(router, blobs, maxBytes: maxBlobBytes);
  return const Pipeline()
      .addMiddleware(bearerAuth(token, publicPaths: _publicPaths))
      .addHandler(router.call);
}

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

Response _health(Request request) =>
    _json(HttpStatus.ok, {'status': 'ok', 'protocol': protocolVersion, 'blobs': true});

Response _notFound(Request request) => _json(HttpStatus.notFound, {'error': 'not found'});

/// `POST /v1/push`: validates every record, then applies all atomically.
Future<Response> _push(Request request, RecordStore store) async {
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
  if (rawRecords.length > maxPushRecords) {
    return _tooLarge('at most $maxPushRecords records per push');
  }

  final records = <SyncRecord>[];
  for (var i = 0; i < rawRecords.length; i++) {
    try {
      records.add(SyncRecord.fromJson(rawRecords[i]));
    } on RecordValidationException catch (e) {
      return _badRequest('records[$i]: ${e.message}');
    }
  }

  final result = store.push(records);
  return _json(HttpStatus.ok, {
    'applied': result.applied,
    'ignored': result.ignored,
    'serverSeq': result.serverSeq,
  });
}

/// `GET /v1/pull?since=&limit=`: one page of the change feed.
Response _pull(Request request, RecordStore store) {
  final params = request.url.queryParameters;
  final since = _intParam(params['since'], fallback: 0);
  final limit = _intParam(params['limit'], fallback: defaultPullLimit);
  if (since == null || since < 0) {
    return _badRequest('since must be a non-negative integer');
  }
  if (limit == null || limit < 1) {
    return _badRequest('limit must be a positive integer');
  }

  final page = store.pull(since: since, limit: limit > maxPullLimit ? maxPullLimit : limit);
  return _json(HttpStatus.ok, {
    'records': [for (final r in page.records) r.toJson()],
    'nextSince': page.nextSince,
    'hasMore': page.hasMore,
  });
}

/// Parses an optional integer query parameter; `null` means invalid.
int? _intParam(String? raw, {required int fallback}) => raw == null ? fallback : int.tryParse(raw);

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

Response _badRequest(String message) => _json(HttpStatus.badRequest, {'error': message});

Response _tooLarge(String message) => _json(HttpStatus.requestEntityTooLarge, {'error': message});

Response _json(int status, Object body) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json; charset=utf-8'},
);
