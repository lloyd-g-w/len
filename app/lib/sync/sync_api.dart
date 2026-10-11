import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../data/syncable.dart';

/// What kind of failure a [SyncException] reports.
enum SyncFailure {
  /// The server could not be reached (or did not answer in time).
  network,

  /// The server rejected the access token.
  auth,

  /// The server (or a proxy in front of it) refused a request as too large.
  tooLarge,

  /// Anything else: an error status or an unexpected response.
  server,
}

/// Thrown for any failed sync request, with a user-presentable message.
class SyncException implements Exception {
  const SyncException(this.message, {this.kind = SyncFailure.server});
  final String message;
  final SyncFailure kind;

  @override
  String toString() => message;
}

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

/// What `GET /v1/health` reports; fields are null when the server did not
/// say (older servers, or a proxy answering instead of the server).
class ServerInfo {
  const ServerInfo({this.maxBlobBytes, this.blobsCollectedAt});

  /// Nothing known.
  static const unknown = ServerInfo();

  /// Largest blob the server accepts.
  final int? maxBlobBytes;

  /// When the server last deleted blobs by garbage collection (0 = never).
  final int? blobsCollectedAt;
}

/// Thin HTTP client for the Len sync server (docs/SYNC_PROTOCOL.md).
class SyncApi {
  /// Throws [SyncException] if [baseUrl] is not an http(s) URL.
  SyncApi({
    required String baseUrl,
    required this.token,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : baseUri = _parseBaseUrl(baseUrl),
       _client = client ?? http.Client();

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

  /// Checks that the server is reachable and the token is accepted.
  Future<void> check() async {
    await _send(
      () => _client.get(_uri('v1/pull', {'since': '0', 'limit': '1'}), headers: _headers),
    );
  }

  /// Reads `/v1/health`. Throws [SyncException] only if the server cannot
  /// be reached; any other unexpected answer gives [ServerInfo.unknown].
  Future<ServerInfo> serverInfo() async {
    final response = await _request(() => _client.get(_uri('v1/health')));
    final json = response.statusCode == 200 ? _decodeObject(response.body) : null;
    if (json == null) return ServerInfo.unknown;
    int? positive(Object? v) => v is int && v > 0 ? v : null;
    final collected = json['blobsCollectedAt'];
    return ServerInfo(
      maxBlobBytes: positive(json['maxBlobBytes']),
      blobsCollectedAt: collected is int && collected >= 0 ? collected : null,
    );
  }

  /// Uploads [records], split into as many requests as the server's count
  /// and size limits require.
  ///
  /// Returns the records that were not sent because a single one exceeds
  /// [maxRecordBytes]; everything else was accepted by the server.
  Future<List<SyncRecord>> push(List<SyncRecord> records) async {
    final oversized = <SyncRecord>[];
    var batch = <String>[];
    var batchBytes = 0;

    Future<void> flush() async {
      if (batch.isEmpty) return;
      final body = '{"records":[${batch.join(',')}]}';
      batch = [];
      batchBytes = 0;
      await _send(() => _client.post(_uri('v1/push'), headers: _headers, body: body));
    }

    for (final record in records) {
      final encoded = jsonEncode(record.toJson());
      // Records are mostly ASCII (base64 points); measure exactly anyway.
      final bytes = utf8.encode(encoded).length;
      if (bytes > maxRecordBytes) {
        oversized.add(record);
        continue;
      }
      if (batch.length >= maxPushRecords || batchBytes + bytes > pushBytesTarget) {
        await flush();
      }
      batch.add(encoded);
      batchBytes += bytes + 1; // + separator
    }
    await flush();
    return oversized;
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
      throw const SyncException('Unexpected response from sync server');
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
      throw SyncException('Cannot reach sync server: $e', kind: SyncFailure.network);
    }
  }

  static void _expectOk(http.Response response) {
    switch (response.statusCode) {
      case 200:
        return;
      case 401:
        throw const SyncException('Sync server rejected the access token', kind: SyncFailure.auth);
      case 413:
        throw const SyncException(
          'Sync server refused an oversized file',
          kind: SyncFailure.tooLarge,
        );
      case final status:
        throw SyncException(
          'Sync server error $status${_errorDetail(_decodeObject(response.body))}',
        );
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
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on Exception catch (e) {
      throw SyncException('Cannot reach sync server: $e', kind: SyncFailure.network);
    }
    final json = _decodeObject(response.body);
    switch (response.statusCode) {
      case 200:
        if (json != null) return json;
        throw const SyncException('Unexpected response from sync server');
      case 401:
        throw const SyncException('Sync server rejected the access token', kind: SyncFailure.auth);
      case 413:
        throw const SyncException(
          'Sync server refused an oversized request',
          kind: SyncFailure.tooLarge,
        );
      case final status:
        throw SyncException('Sync server error $status${_errorDetail(json)}');
    }
  }

  /// The server's `{"error": "…"}` message, shortened; never raw bodies,
  /// which may be large HTML pages from a proxy.
  static String _errorDetail(Map<String, Object?>? json) {
    final error = json?['error'];
    if (error is! String || error.isEmpty) return '';
    return ': ${error.length > 200 ? '${error.substring(0, 200)}…' : error}';
  }

  static Map<String, Object?>? _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
