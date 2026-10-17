import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:len/sync/live_channel.dart';
import 'package:len/sync/sync_errors.dart';
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

  /// The server's event streams (`/v1/events`), ended by [restart].
  late server.ChangeEvents events;

  /// The server's live connections (`/v1/live`), closed by [restart].
  late server.LiveHub live;

  /// Whether live connections are refused (a proxy that does not pass
  /// WebSockets on); the rest of the API works.
  bool liveDown = false;

  /// Times the server was restarted.
  int restarts = 0;

  /// Whether the server is down: connections are refused.
  bool down = false;

  /// The most records a pull page holds, if fewer than clients ask for (a
  /// server may cut pages short: long pulls in tests).
  int? maxPage;

  void _open() {
    store = server.RecordStore.open('${dir.path}/len.db');
    blobs = server.BlobStore.open('${dir.path}/blobs');
    events = server.ChangeEvents();
    live = server.LiveHub();
    _handler = server.buildHandler(
      store: store,
      blobs: blobs,
      token: token,
      events: events,
      live: live,
    );
  }

  /// Closes the database and opens it again. Requests in flight keep the
  /// old (closed) store and fail with 500, as on a crash.
  void restart() {
    unawaited(events.close());
    unawaited(live.close());
    store.close();
    restarts++;
    _open();
  }

  /// Serves [request] (its URL's path from `/v1/…`), with [body] instead
  /// of the request's own if given.
  Future<http.StreamedResponse> handle(http.BaseRequest request, {Stream<List<int>>? body}) async {
    if (down) throw http.ClientException('Connection refused', request.url);
    var url = request.url.replace(scheme: 'http', host: 'sync.test');
    final limit = int.tryParse(url.queryParameters['limit'] ?? '');
    if (url.path == '/v1/pull' && maxPage != null && limit != null && limit > maxPage!) {
      url = url.replace(queryParameters: {...url.queryParameters, 'limit': '$maxPage'});
    }
    final response = await _handler(
      shelf.Request(
        request.method,
        url,
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

  /// Opens a live connection with [token], in memory (no sockets): what
  /// `/v1/live` does once the WebSocket is up. [cut] is called with a
  /// function that breaks the connection (a network failing).
  Future<LiveChannel> connectLive(String token, {void Function(void Function() cut)? cut}) async {
    if (down || liveDown) {
      throw SyncException.unreachable(http.ClientException('Connection refused'));
    }
    if (token != RealServer.token) {
      throw SyncException.unreachable(http.ClientException('not upgraded (401)'));
    }
    if (!live.acceptsMore) throw SyncException.unreachable(http.ClientException('503'));
    final toServer = StreamController<Object?>();
    final toClient = StreamController<Object?>();
    final channel = _MemoryLiveChannel(toClient.stream, toServer);
    live.accept(
      server.LivePeer(
        incoming: toServer.stream,
        outgoing: toClient,
        close: (code, reason) async => channel.end(),
        destroy: channel.end,
      ),
    );
    cut?.call(channel.end);
    return channel;
  }

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
    unawaited(events.close());
    unawaited(live.close());
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

/// A live connection's client end in memory: what the server sends
/// arrives through [messages] until either side ends it.
class _MemoryLiveChannel implements LiveChannel {
  _MemoryLiveChannel(Stream<Object?> fromServer, this._toServer) {
    _in = fromServer.listen((m) => _messages.add(m! as String), onDone: end);
  }

  final StreamController<Object?> _toServer;
  late final StreamSubscription<Object?> _in;
  final _messages = StreamController<String>();

  @override
  Stream<String> get messages => _messages.stream;

  @override
  void send(String message) {
    if (!_toServer.isClosed) _toServer.add(message);
  }

  @override
  void close() => end();

  /// Ends the connection both ways (the server sees its client leave).
  void end() {
    if (!_toServer.isClosed) unawaited(_toServer.close());
    unawaited(_in.cancel());
    if (!_messages.isClosed) unawaited(_messages.close());
  }
}
