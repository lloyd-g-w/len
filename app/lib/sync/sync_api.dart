import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/syncable.dart';

/// Thrown for any failed sync request, with a user-presentable message.
class SyncException implements Exception {
  const SyncException(this.message);
  final String message;

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

/// Thin HTTP client for the Len sync server (docs/SYNC_PROTOCOL.md).
class SyncApi {
  /// Throws [SyncException] if [baseUrl] is not an http(s) URL.
  SyncApi({
    required String baseUrl,
    required this.token,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  })  : baseUri = _parseBaseUrl(baseUrl),
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
    await _send(() => _client.get(_uri('v1/pull', {'since': '0', 'limit': '1'}), headers: _headers));
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
      () => _client.get(
        _uri('v1/pull', {'since': '$since', 'limit': '$limit'}),
        headers: _headers,
      ),
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
    return PullPage(
      records: records,
      nextSince: nextSince,
      hasMore: hasMore,
      malformed: malformed,
    );
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
      throw SyncException('Cannot reach sync server: $e');
    }
    final json = _decodeObject(response.body);
    switch (response.statusCode) {
      case 200:
        if (json != null) return json;
        throw const SyncException('Unexpected response from sync server');
      case 401:
        throw const SyncException('Sync server rejected the access token');
      case 413:
        throw const SyncException('Sync server refused an oversized request');
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
