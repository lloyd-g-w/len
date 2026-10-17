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
import 'live_api.dart';
import 'live_hub.dart';
import 'live_tickets.dart';
import 'push_request.dart';
import 'record_store.dart';

/// Protocol version reported by `/v1/health`.
const protocolVersion = 1;

/// Maximum push body size in bytes (32 MiB).
const maxPushBytes = 32 * 1024 * 1024;

/// Default and maximum page size for pull.
const defaultPullLimit = 500;
const maxPullLimit = 1000;

/// Paths reachable without a bearer token (`/v1/live` checks the token or
/// a ticket itself).
const _publicPaths = {'v1/health', 'v1/live'};

/// Builds the complete request handler: CORS middleware ([cors], outermost,
/// so preflights and auth errors are covered), then auth, then the protocol
/// routes. Logging is left to the caller.
///
/// Blob uploads are limited to [maxBlobBytes]; the push body limit
/// ([maxPushBytes]) does not apply to them, and an upload pausing longer
/// than [blobIdleTimeout] is abandoned.
///
/// `GET /v1/events` streams through [events], `GET /v1/live` connects to
/// [live] (new ones if not given; the caller closes them at shutdown).
Handler buildHandler({
  required RecordStore store,
  required BlobStore blobs,
  required String token,
  int maxBlobBytes = defaultMaxBlobBytes,
  Duration blobIdleTimeout = defaultBlobIdleTimeout,
  CorsPolicy cors = const CorsPolicy.any(),
  ChangeEvents? events,
  LiveHub? live,
  LiveTickets? tickets,
}) {
  final feed = _Feed(store, events ?? ChangeEvents(), live ?? LiveHub());
  final liveTickets = tickets ?? LiveTickets();
  final router = Router(notFoundHandler: _notFound)
    ..get('/v1/health', (Request request) => _health(store, maxBlobBytes))
    ..post('/v1/push', (Request request) => _push(request, feed))
    ..get('/v1/pull', (Request request) => _pull(request, feed))
    ..get(
      '/v1/events',
      (Request request) => feed.events.subscribe(seq: store.currentSeq(), serverId: store.serverId),
    )
    ..get(
      '/v1/live',
      (Request request) => upgradeLive(
        request,
        hub: feed.live,
        tickets: liveTickets,
        authorized: (header) => _authorized(header, utf8.encode(token)),
        cors: cors,
      ),
    )
    ..post('/v1/live/ticket', (Request request) => issueTicket(liveTickets));
  addBlobRoutes(router, blobs, maxBytes: maxBlobBytes, idleTimeout: blobIdleTimeout);
  return const Pipeline()
      .addMiddleware(corsMiddleware(cors))
      .addMiddleware(_internalErrors)
      .addMiddleware(bearerAuth(token, publicPaths: _publicPaths))
      .addHandler(router.call);
}

/// The store with whoever hears of its changes: event streams and live
/// connections.
class _Feed {
  _Feed(this.store, this.events, this.live) {
    live
      ..feed = (() => (seq: store.currentSeq(), serverId: store.serverId))
      ..onPush = _livePush;
  }

  final RecordStore store;
  final ChangeEvents events;
  final LiveHub live;

  /// Applies [request] and tells everyone but [from] (a live pusher) what
  /// it stored. Throws [HistoryLostException] (after telling everyone).
  PushResult push(PushRequest request, {LiveConnection? from}) {
    final PushResult result;
    try {
      result = store.push(request.records, since: request.since);
    } on HistoryLostException {
      historyLost();
      rethrow;
    }
    if (result.applied > 0) {
      live.publishRecords(result.stored, except: from);
      events.publish(seq: result.serverSeq, serverId: store.serverId);
    }
    return result;
  }

  /// The server took a new id: every client resets.
  void historyLost() {
    events.publish(seq: store.currentSeq(), serverId: store.serverId);
    live.publishResync();
  }

  /// A live connection's `push`: like `POST /v1/push`, and with
  /// `"current": true` applied only if the client has every change up to
  /// the newest seq (else answered `stale`: it applies what is on its way
  /// and pushes again), so rows edited in place and deletions are judged
  /// by a client that saw what they race (docs/SYNC_PROTOCOL.md).
  Map<String, Object?> _livePush(Map<String, Object?> message, LiveConnection from) {
    final id = message['id'];
    try {
      final request = parsePush(message);
      final seq = store.currentSeq();
      if (message['current'] == true && request.since < seq) {
        return {'type': 'pushed', 'id': ?id, 'stale': true, 'serverSeq': seq};
      }
      final result = push(request, from: from);
      return {
        'type': 'pushed',
        'id': ?id,
        'applied': result.applied,
        'ignored': result.ignored,
        'serverSeq': result.serverSeq,
      };
    } on PushRejected catch (e) {
      return {
        'type': 'error',
        'id': ?id,
        'status': e.status,
        'error': e.message,
        'index': ?e.index,
      };
    } on HistoryLostException {
      return {'type': 'error', 'id': ?id, 'status': HttpStatus.conflict, 'error': _historyLostText};
    }
  }
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
      if (!_authorized(request.headers['authorization'], expected)) {
        return _json(HttpStatus.unauthorized, {'error': 'unauthorized'});
      }
      return inner(request);
    };
  };
}

/// Whether the `Authorization` [header] carries the token ([expected]).
bool _authorized(String? header, List<int> expected) {
  final presented = _bearerToken(header);
  return presented != null && constantTimeEquals(utf8.encode(presented), expected);
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
Future<Response> _push(Request request, _Feed feed) async {
  final Object? body;
  try {
    body = await _readJsonBody(request, maxPushBytes);
  } on _TooLarge {
    return _tooLarge('body exceeds $maxPushBytes bytes');
  } on FormatException {
    return _badRequest('body must be valid UTF-8 JSON');
  }
  final PushResult result;
  try {
    result = feed.push(parsePush(body));
  } on PushRejected catch (e) {
    return _json(e.status, {'error': e.message, 'index': ?e.index});
  } on HistoryLostException {
    return _historyLost();
  }
  return _json(HttpStatus.ok, {
    'applied': result.applied,
    'ignored': result.ignored,
    'serverSeq': result.serverSeq,
  });
}

/// `GET /v1/pull?since=&limit=`: one page of the change feed.
Response _pull(Request request, _Feed feed) {
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
    page = feed.store.pull(since: since, limit: limit > maxPullLimit ? maxPullLimit : limit);
  } on HistoryLostException {
    feed.historyLost();
    return _historyLost();
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

/// 409: the client has seen changes this server no longer has. (The server
/// took a new id; event streams and live connections heard of it.)
Response _historyLost() => _json(HttpStatus.conflict, {'error': _historyLostText});

const _historyLostText =
    'history lost: the server was restored or replaced; upload everything again';

Response _badRequest(String message) => _json(HttpStatus.badRequest, {'error': message});

Response _tooLarge(String message) => _json(HttpStatus.requestEntityTooLarge, {'error': message});

Response _json(int status, Object body) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json; charset=utf-8'},
);
