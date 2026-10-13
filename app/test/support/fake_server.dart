import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/sync/sync_api.dart';

/// Minimal in-memory implementation of docs/SYNC_PROTOCOL.md.
class FakeServer {
  final Map<String, Map<String, Object?>> _records = {};
  int _seq = 0;
  static const token = 'secret-token-123456';

  /// Body sizes (bytes) and record counts of every push received.
  final List<({int bytes, int count})> pushes = [];

  /// Number of pull requests received.
  int pulls = 0;

  /// Extra raw records served by pull (for malformed-input tests).
  final List<Object?> injected = [];

  /// Stored blobs by SHA-256, and the order of blob and push requests.
  final Map<String, Uint8List> blobs = {};
  final List<String> log = [];

  /// `/v1/health` fields: the advertised blob limit, the last garbage
  /// collection and the server id (unique per fake server).
  int maxBlobBytes = 200 * 1024 * 1024;
  int blobsCollectedAt = 0;
  String serverId = 'server-${_servers++}';
  static int _servers = 0;

  /// Forgets every record after [seq] (keeping blobs), like a server
  /// restored from a backup taken at that point.
  void restoreBackup(int seq) {
    _records.removeWhere((_, r) => (r['seq']! as int) > seq);
    _seq = seq;
  }

  /// Rejects a request whose `since` is beyond the newest seq: the client
  /// saw changes this server lost. Takes a new id, like the real server.
  http.Response? _historyLost(Object? since) {
    if (since is! int || since <= _seq) return null;
    serverId = 'server-${_servers++}';
    return http.Response('{"error":"history lost"}', 409);
  }

  /// Blob uploads larger than this are refused with 413 (a proxy, or a
  /// server not advertising its limit).
  int? rejectBlobsAbove;

  /// Ids of records the server refuses as invalid (400 naming the index of
  /// the first one in the push, applying nothing).
  final Set<String> invalidRecords = {};

  /// Blob uploads that fail with 500.
  final Set<String> failingPuts = {};

  /// Every blob upload attempted, in order.
  final List<String> putAttempts = [];

  /// The stored record `collection/id`, or null.
  Map<String, Object?>? stored(String collection, String id) => _records['$collection/$id'];

  late final MockClient client = MockClient((request) async {
    if (request.url.path == '/v1/health') {
      return http.Response(
        jsonEncode({
          'status': 'ok',
          'protocol': 1,
          'maxBlobBytes': maxBlobBytes,
          'blobsCollectedAt': blobsCollectedAt,
          'serverId': serverId,
        }),
        200,
      );
    }
    if (request.headers['Authorization'] != 'Bearer $token') {
      return http.Response('{"error":"unauthorized"}', 401);
    }
    final path = request.url.path;
    if (path.startsWith('/v1/blobs/')) {
      final sha = path.substring('/v1/blobs/'.length);
      log.add('${request.method} blob');
      switch (request.method) {
        case 'HEAD':
          return http.Response('', blobs.containsKey(sha) ? 200 : 404);
        case 'GET':
          final b = blobs[sha];
          return b == null
              ? http.Response('{"error":"not found"}', 404)
              : http.Response.bytes(b, 200);
        case 'PUT':
          putAttempts.add(sha);
          if (failingPuts.contains(sha)) return http.Response('{"error":"disk full"}', 500);
          if (request.bodyBytes.length > (rejectBlobsAbove ?? 1 << 62)) {
            return http.Response('{"error":"blob too large"}', 413);
          }
          if (sha256.convert(request.bodyBytes).toString() != sha) {
            return http.Response('{"error":"hash mismatch"}', 400);
          }
          blobs[sha] = request.bodyBytes;
          return http.Response(jsonEncode({'sha256': sha, 'size': request.bodyBytes.length}), 200);
      }
    }
    if (path == '/v1/push') log.add('push');
    switch (path) {
      case '/v1/push':
        if (request.bodyBytes.length > 32 * 1024 * 1024) {
          return http.Response('{"error":"too large"}', 413);
        }
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final records = body['records']! as List;
        if (_historyLost(body['since'] ?? 0) case final lost?) return lost;
        if (records.length > 1000) return http.Response('{"error":"too many"}', 413);
        for (var i = 0; i < records.length; i++) {
          if (invalidRecords.contains((records[i] as Map)['id'])) {
            return http.Response(jsonEncode({'error': 'records[$i]: invalid', 'index': i}), 400);
          }
        }
        pushes.add((bytes: request.bodyBytes.length, count: records.length));
        for (final r in (body['records']! as List).cast<Map<String, Object?>>()) {
          final key = '${r['collection']}/${r['id']}';
          final existing = _records[key];
          final newer =
              existing == null ||
              (r['updatedAt']! as int) > (existing['updatedAt']! as int) ||
              (r['updatedAt'] == existing['updatedAt'] &&
                  (r['deviceId']! as String).compareTo(existing['deviceId']! as String) > 0);
          if (newer) _records[key] = {...r, 'seq': ++_seq};
        }
        return http.Response(jsonEncode({'applied': 0, 'ignored': 0, 'serverSeq': _seq}), 200);
      case '/v1/pull':
        pulls++;
        final since = int.parse(request.url.queryParameters['since'] ?? '0');
        if (_historyLost(since) case final lost?) return lost;
        final limit = int.parse(request.url.queryParameters['limit'] ?? '500');
        final all = _records.values.where((r) => (r['seq']! as int) > since).toList()
          ..sort((a, b) => (a['seq']! as int).compareTo(b['seq']! as int));
        final page = all.take(limit).toList();
        return http.Response(
          jsonEncode({
            'records': [...injected, ...page],
            'nextSince': page.isEmpty ? since : page.last['seq'],
            'hasMore': all.length > page.length,
          }),
          200,
        );
    }
    return http.Response('', 404);
  });
}

AppServices device(FakeServer server) {
  final services = AppServices.create(AppDatabase.inMemory());
  services.sync.configure(url: 'http://sync.test', token: FakeServer.token);
  return services;
}

SyncApi apiFor(FakeServer server) =>
    SyncApi(baseUrl: 'http://sync.test', token: FakeServer.token, client: server.client);

Stroke bigStroke(String id, String surface, int points) => Stroke(
  id: id,
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: 0xFF000000,
  width: 2,
  points: [for (var i = 0; i < points; i++) StrokePoint(i.toDouble(), 0, 0.5)],
  createdAt: 1,
);

/// A pull response with the given records and one page.
http.Response pullResponse(List<Object?> records, {int nextSince = 1, bool hasMore = false}) =>
    http.Response(
      jsonEncode({'records': records, 'nextSince': nextSince, 'hasMore': hasMore}),
      200,
    );
