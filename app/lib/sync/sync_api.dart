import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/syncable.dart';
import '../platform/pull_decoder.dart';
import 'pull_page.dart';
import 'server_events.dart';
import 'server_info.dart';
import 'sync_errors.dart';

export 'pull_page.dart' show PullPage;
export 'server_events.dart' show ServerEvent;
export 'server_info.dart';
export 'sync_errors.dart';

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

  /// The push body size aimed at: [pushBytesTarget], less after a proxy
  /// refused a body as too large.
  int _pushBytes = pushBytesTarget;

  /// Largest single encoded record that is sent at all (server body limit
  /// minus room for the envelope).
  static const maxRecordBytes = 32 * 1024 * 1024 - 1024;

  /// Page size requested from `/v1/pull`: the server's largest (fewer
  /// round trips; pages are decoded off the UI thread and applied in slices).
  static const pullLimit = 1000;

  final Uri baseUri;
  final String token;
  final Duration timeout;
  final http.Client _client;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json; charset=utf-8',
  };

  /// Checks that a compatible Len server answers and accepts the token.
  Future<ServerInfo> check() async {
    final info = await serverInfo();
    await _send(
      () => _client.get(_uri('v1/pull', {'since': '0', 'limit': '1'}), headers: _headers),
    );
    return info;
  }

  /// Reads `/v1/health`. Throws [SyncException] if the server cannot be
  /// reached or is not a compatible Len sync server. Sends the token too
  /// (the server ignores it), so a proxy guarding every path lets it pass.
  Future<ServerInfo> serverInfo() async {
    final response = await _request(() => _client.get(_uri('v1/health'), headers: _headers));
    if (response.statusCode != 200) {
      throw SyncException.status(response.statusCode, response.body);
    }
    final json = decodeObject(response.body);
    if (json == null) {
      throw SyncException.unreadable(response.bodyBytes, otherwise: SyncException.notLen);
    }
    return ServerInfo.fromJson(json);
  }

  /// Uploads [records], split into as many requests as the server's count
  /// and size limits require. [since] is the newest seq pulled from this
  /// server; a server that no longer has it refuses the push
  /// ([SyncFailure.historyLost]).
  ///
  /// Returns the records that were not sent because a single one exceeds
  /// [maxRecordBytes] or cannot be encoded as JSON, or that the server
  /// rejected as invalid (`400` naming its `index`; the rest of its request
  /// is sent again without it); everything else was accepted by the server.
  /// [onStored] hears what each request stored: how many records, and the
  /// server's newest seq after it (theirs are the [applied] seqs up to it).
  Future<List<SyncRecord>> push(
    List<SyncRecord> records, {
    required int since,
    void Function(int applied, int serverSeq)? onStored,
  }) async {
    final unsent = <SyncRecord>[];
    var batch = <({SyncRecord record, String json})>[];
    var batchBytes = 0;

    Future<void> send(List<({SyncRecord record, String json})> sending) async {
      while (sending.isNotEmpty) {
        final body = '{"since":$since,"records":[${sending.map((r) => r.json).join(',')}]}';
        final response = await _request(
          () => _client.post(_uri('v1/push'), headers: _headers, body: body),
        );
        if (response.statusCode == 413) {
          // A reverse proxy in front of the server may allow smaller bodies
          // than the server (nginx: 1 MiB by default): send less at a time,
          // and skip a record that cannot pass on its own (it stays dirty).
          _pushBytes = min(_pushBytes, body.length ~/ 2);
          if (sending.length == 1) {
            final record = sending.single.record;
            debugPrint('Too large for the sync server: ${record.collection}/${record.id}');
            unsent.add(record);
            return;
          }
          final half = sending.length ~/ 2;
          await send(sending.sublist(0, half));
          await send(sending.sublist(half));
          return;
        }
        final rejected = _rejectedIndex(response, sending.length);
        if (rejected == null) {
          _expectOk(response);
          final json = decodeObject(response.body);
          if (json == null) throw SyncException.unreadable(response.bodyBytes);
          if (json case {'applied': final int applied, 'serverSeq': final int serverSeq}) {
            onStored?.call(applied, serverSeq);
          }
          return;
        }
        final record = sending.removeAt(rejected).record;
        debugPrint(
          'The sync server rejected ${record.collection}/${record.id}: '
          '${decodeObject(response.body)?['error']}',
        );
        unsent.add(record);
      }
    }

    Future<void> flush() async {
      final sending = batch;
      batch = [];
      batchBytes = 0;
      await send(sending);
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
      if (batch.length >= maxPushRecords || batchBytes + bytes > _pushBytes) {
        await flush();
      }
      batch.add((record: record, json: encoded));
      batchBytes += bytes + 1; // + separator
    }
    await flush();
    return unsent;
  }

  /// Fetches one page of changes after [since].
  ///
  /// Malformed records are dropped (and counted) rather than failing the
  /// whole page, so one bad record can never block sync forever. Pages are
  /// decoded off the UI thread where the platform can ([decodePulled]).
  Future<PullPage> pull({required int since, int limit = pullLimit}) async {
    final body = await pullBody(since: since, limit: limit);
    return await decodePulled(body, since: since) ?? (throw SyncException.unreadable(body));
  }

  /// Fetches one page of changes after [since], undecoded (see
  /// `decodePullPage`).
  Future<Uint8List> pullBody({required int since, int limit = pullLimit}) async {
    final response = await _request(
      () => _client.get(_uri('v1/pull', {'since': '$since', 'limit': '$limit'}), headers: _headers),
    );
    _expectOk(response);
    return response.bodyBytes;
  }

  /// Opens the server's event stream (`/v1/events`): an event whenever
  /// its change feed moves on, `null` for each heartbeat. Throws
  /// [SyncException] if it cannot be opened; the stream ends or fails when
  /// the connection does (or [close] is called).
  Future<Stream<ServerEvent?>> events() async {
    // No other headers: in a browser each would need the server's CORS
    // permission (Accept is always allowed).
    final request = http.Request('GET', _uri('v1/events'))
      ..headers.addAll({'Authorization': 'Bearer $token', 'Accept': 'text/event-stream'});
    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(timeout);
    } on Exception catch (e) {
      throw SyncException.unreachable(e);
    }
    if (response.statusCode != 200) {
      final body = await response.stream
          .bytesToString()
          .timeout(timeout, onTimeout: () => '')
          .catchError((Object _) => '');
      throw SyncException.status(response.statusCode, body);
    }
    return parseServerEvents(response.stream);
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

  /// The position of the record a `400` answer to a push rejects, if it
  /// names one of the [count] records sent.
  static int? _rejectedIndex(http.Response response, int count) {
    if (response.statusCode != 400) return null;
    final index = decodeObject(response.body)?['index'];
    return index is int && index >= 0 && index < count ? index : null;
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
    return decodeObject(response.body) ?? (throw SyncException.unreadable(response.bodyBytes));
  }
}
