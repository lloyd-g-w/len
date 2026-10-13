import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/syncable.dart';
import 'sync_errors.dart';

export 'sync_errors.dart';

/// One page of the server's change feed.
class PullPage {
  const PullPage({
    required this.records,
    required this.nextSince,
    required this.hasMore,
    this.malformed = 0,
  });

  final List<SyncRecord> records;
  final int nextSince;
  final bool hasMore;

  /// Records on this page that could not be parsed and were dropped.
  final int malformed;
}

/// What `GET /v1/health` reports.
class ServerInfo {
  const ServerInfo({
    required this.serverId,
    required this.maxBlobBytes,
    required this.blobsCollectedAt,
  });

  /// The protocol version this app speaks.
  static const protocol = 1;

  /// Identifies the server's change history; a new id means another server
  /// (or one restored from a backup).
  final String serverId;

  /// Largest blob the server accepts.
  final int maxBlobBytes;

  /// When the server last deleted blobs by garbage collection (0 = never).
  final int blobsCollectedAt;

  /// Parses a health answer; throws [SyncException] when it is not one of a
  /// Len sync server speaking [protocol].
  factory ServerInfo.fromJson(Map<String, Object?>? json) {
    if (json == null || json['status'] != 'ok') throw SyncException.notLen;
    final version = json['protocol'];
    if (version is! int) throw SyncException.notLen;
    if (version > protocol) throw SyncException.serverTooNew;
    final (id, max, collected) = (json['serverId'], json['maxBlobBytes'], json['blobsCollectedAt']);
    if (version < protocol || id is! String || id.isEmpty || max is! int || collected is! int) {
      throw SyncException.serverTooOld;
    }
    if (max <= 0 || collected < 0) throw SyncException.unexpected;
    return ServerInfo(serverId: id, maxBlobBytes: max, blobsCollectedAt: collected);
  }
}

/// Thin HTTP client for the Len sync server (docs/SYNC_PROTOCOL.md).
class SyncApi {
  /// Throws [SyncException] if [baseUrl] is not an http(s) URL or [token]
  /// cannot be sent in an HTTP header.
  SyncApi({
    required String baseUrl,
    required this.token,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : baseUri = _parseBaseUrl(baseUrl),
       _client = client ?? http.Client() {
    if (!_tokenChars.hasMatch(token)) {
      throw const SyncException(
        'The access token can only contain letters, digits and punctuation — paste it again',
        kind: SyncFailure.auth,
      );
    }
  }

  /// Printable ASCII without spaces: what an HTTP header can carry (server
  /// tokens are e.g. hex from `openssl rand -hex 32`).
  static final _tokenChars = RegExp(r'^[!-~]*$');

  /// Server limit on records per push.
  static const maxPushRecords = 1000;

  /// Target request body size. Pushes are split to stay below it, which
  /// keeps requests well under the server's 32 MiB limit and lets slow
  /// connections make progress.
  static const pushBytesTarget = 4 * 1024 * 1024;

  /// Largest single encoded record that is sent at all (server body limit
  /// minus room for the envelope).
  static const maxRecordBytes = 32 * 1024 * 1024 - 1024;

  /// Page size requested from `/v1/pull` (the server caps it at 1000).
  static const pullLimit = 500;

  final Uri baseUri;
  final String token;
  final Duration timeout;
  final http.Client _client;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json; charset=utf-8',
  };

  /// Checks that a compatible Len server answers and accepts the token.
  Future<void> check() async {
    await serverInfo();
    await _send(
      () => _client.get(_uri('v1/pull', {'since': '0', 'limit': '1'}), headers: _headers),
    );
  }

  /// Reads `/v1/health`. Throws [SyncException] if the server cannot be
  /// reached or is not a compatible Len sync server. Sends the token too
  /// (the server ignores it), so a proxy guarding every path lets it pass.
  Future<ServerInfo> serverInfo() async {
    final response = await _request(() => _client.get(_uri('v1/health'), headers: _headers));
    if (response.statusCode != 200) {
      throw SyncException.status(response.statusCode, response.body);
    }
    return ServerInfo.fromJson(decodeObject(response.body));
  }

  /// Uploads [records], split into as many requests as the server's count
  /// and size limits require. [since] is the newest seq pulled from this
  /// server; a server that no longer has it refuses the push
  /// ([SyncFailure.historyLost]).
  ///
  /// Returns the records that were not sent because a single one exceeds
  /// [maxRecordBytes] or cannot be encoded as JSON; everything else was
  /// accepted by the server.
  Future<List<SyncRecord>> push(List<SyncRecord> records, {required int since}) async {
    final unsent = <SyncRecord>[];
    var batch = <String>[];
    var batchBytes = 0;

    Future<void> flush() async {
      if (batch.isEmpty) return;
      final body = '{"since":$since,"records":[${batch.join(',')}]}';
      batch = [];
      batchBytes = 0;
      await _send(() => _client.post(_uri('v1/push'), headers: _headers, body: body));
    }

    for (final record in records) {
      final String encoded;
      try {
        encoded = jsonEncode(record.toJson());
      } on JsonUnsupportedObjectError catch (e) {
        // A value JSON cannot hold (NaN or infinity from a geometry bug):
        // skip this record rather than failing the push of every other.
        debugPrint('Cannot encode ${record.collection}/${record.id}: ${e.cause ?? e}');
        unsent.add(record);
        continue;
      }
      // Records are mostly ASCII (base64 points); measure exactly anyway.
      final bytes = utf8.encode(encoded).length;
      if (bytes > maxRecordBytes) {
        debugPrint('Not syncing oversized ${record.collection}/${record.id}');
        unsent.add(record);
        continue;
      }
      if (batch.length >= maxPushRecords || batchBytes + bytes > pushBytesTarget) {
        await flush();
      }
      batch.add(encoded);
      batchBytes += bytes + 1; // + separator
    }
    await flush();
    return unsent;
  }

  /// Fetches one page of changes after [since].
  ///
  /// Malformed records are dropped (and counted) rather than failing the
  /// whole page, so one bad record can never block sync forever.
  Future<PullPage> pull({required int since, int limit = pullLimit}) async {
    final json = await _send(
      () => _client.get(_uri('v1/pull', {'since': '$since', 'limit': '$limit'}), headers: _headers),
    );
    final rawRecords = json['records'];
    final nextSince = json['nextSince'];
    final hasMore = json['hasMore'];
    if (rawRecords is! List ||
        nextSince is! int ||
        hasMore is! bool ||
        nextSince < since ||
        (hasMore && nextSince == since)) {
      throw SyncException.unexpected;
    }
    final records = <SyncRecord>[];
    var malformed = 0;
    for (final raw in rawRecords) {
      try {
        records.add(SyncRecord.fromJson(raw));
      } on FormatException {
        malformed++;
      }
    }
    return PullPage(records: records, nextSince: nextSince, hasMore: hasMore, malformed: malformed);
  }

  // ---------------------------------------------------------------------------
  // Blobs (docs/SYNC_PROTOCOL.md, "Blobs")

  /// Whether the server already stores blob [sha].
  Future<bool> hasBlob(String sha) async {
    final response = await _request(() => _client.head(_uri('v1/blobs/$sha'), headers: _headers));
    if (response.statusCode == 404) return false;
    _expectOk(response);
    return true;
  }

  /// Uploads blob [sha], [length] bytes streamed from [data]; the server
  /// verifies its hash. A blob the server refuses as too large throws a
  /// [SyncException] of kind [SyncFailure.tooLarge].
  Future<void> putBlob(String sha, Stream<List<int>> data, {required int length}) async {
    final request = http.StreamedRequest('PUT', _uri('v1/blobs/$sha'))
      ..headers.addAll({..._headers, 'Content-Type': 'application/octet-stream'})
      ..contentLength = length;
    unawaited(data.pipe(request.sink));
    final response = await _request(
      () async => http.Response.fromStream(await _client.send(request)),
      // Large uploads may legitimately take a while.
      timeout: const Duration(minutes: 30),
    );
    _expectOk(response);
  }

  /// Downloads a blob, or returns null if the server does not have it.
  Future<Uint8List?> getBlob(String sha) async {
    final response = await _request(
      () => _client.get(_uri('v1/blobs/$sha'), headers: _headers),
      timeout: const Duration(minutes: 30),
    );
    if (response.statusCode == 404) return null;
    _expectOk(response);
    return response.bodyBytes;
  }

  Future<http.Response> _request(
    Future<http.Response> Function() request, {
    Duration? timeout,
  }) async {
    try {
      return await request().timeout(timeout ?? this.timeout);
    } on Exception catch (e) {
      throw SyncException.unreachable(e);
    }
  }

  static void _expectOk(http.Response response) {
    if (response.statusCode != 200) {
      throw SyncException.status(response.statusCode, response.body);
    }
  }

  void close() => _client.close();

  static Uri _parseBaseUrl(String baseUrl) {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) {
      throw const SyncException('Server URL must start with http:// or https://');
    }
    return uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      baseUri.resolve(path).replace(queryParameters: query);

  Future<Map<String, Object?>> _send(Future<http.Response> Function() request) async {
    final response = await _request(request);
    _expectOk(response);
    return decodeObject(response.body) ?? (throw SyncException.unexpected);
  }
}
