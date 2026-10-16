import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:len_sync_server/len_sync_server.dart' as server;
import 'package:shelf/shelf.dart' as shelf;

/// The real sync server (`server/`), run in this process on files of its
/// own, reached through an [http.Client] that hands requests straight to
/// its handler (no sockets). [restart] closes and reopens its database,
/// like a server process restarting.
class RealServer {
  RealServer() : dir = Directory.systemTemp.createTempSync('len-real-server-') {
    _open();
  }

  static const token = 'real-server-token-0123456789';

  final Directory dir;
  late server.RecordStore store;
  late server.BlobStore blobs;
  late shelf.Handler _handler;

  /// Times the server was restarted.
  int restarts = 0;

  void _open() {
    store = server.RecordStore.open('${dir.path}/len.db');
    blobs = server.BlobStore.open('${dir.path}/blobs');
    _handler = server.buildHandler(store: store, blobs: blobs, token: token);
  }

  /// Closes the database and opens it again. Requests in flight keep the
  /// old (closed) store and fail with 500, as on a crash.
  void restart() {
    store.close();
    restarts++;
    _open();
  }

  /// Serves [request] (its URL's path from `/v1/…`), with [body] instead
  /// of the request's own if given.
  Future<http.StreamedResponse> handle(http.BaseRequest request, {Stream<List<int>>? body}) async {
    final response = await _handler(
      shelf.Request(
        request.method,
        request.url.replace(scheme: 'http', host: 'sync.test'),
        headers: request.headers,
        body: body ?? request.finalize(),
      ),
    );
    final length = request.method == 'HEAD'
        ? null
        : int.tryParse(response.headers['content-length'] ?? '');
    return http.StreamedResponse(
      request.method == 'HEAD' ? const Stream<List<int>>.empty() : response.read(),
      response.statusCode,
      contentLength: length,
      headers: {for (final e in response.headers.entries) e.key.toLowerCase(): e.value},
      request: request,
    );
  }

  /// A client reaching this server.
  http.Client get client => _HandlerClient(this);

  /// Every live and deleted record the server stores.
  List<server.SyncRecord> records() {
    final out = <server.SyncRecord>[];
    var since = 0;
    while (true) {
      final page = store.pull(since: since, limit: 1000);
      out.addAll(page.records);
      if (!page.hasMore) return out;
      since = page.nextSince;
    }
  }

  void dispose() {
    store.close();
    dir.deleteSync(recursive: true);
  }
}

class _HandlerClient extends http.BaseClient {
  _HandlerClient(this.server);

  final RealServer server;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => server.handle(request);
}
