import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len_sync_server/len_sync_server.dart' as server;
import 'package:shelf/shelf_io.dart' as shelf_io;

/// The real sync server on a loopback socket (real HTTP, real WebSockets),
/// for devices syncing exactly as the app does.
class SocketServer {
  SocketServer._(this._dir, this.store, this.live, this._http);

  static const token = 'socket-server-token-0123456789';

  /// Starts the server. Tests run with the test binding's HTTP stub
  /// (every request answered 400): real connections for this test.
  static Future<SocketServer> start() async {
    final stub = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = stub);
    final dir = Directory.systemTemp.createTempSync('len-socket-server-');
    final store = server.RecordStore.open('${dir.path}/len.db');
    final live = server.LiveHub();
    final http = await shelf_io.serve(
      server.buildHandler(
        store: store,
        blobs: server.BlobStore.open('${dir.path}/blobs'),
        token: token,
        live: live,
      ),
      InternetAddress.loopbackIPv4,
      0,
    );
    return SocketServer._(dir, store, live, http);
  }

  final Directory _dir;
  final server.RecordStore store;
  final server.LiveHub live;
  final HttpServer _http;

  String get url => 'http://127.0.0.1:${_http.port}';

  /// A device syncing with this server like the app (started, foreground).
  Future<AppServices> device() async {
    final s = AppServices.create(AppDatabase.inMemory());
    s.sync.configure(url: url, token: token);
    await s.sync.tokens.save(token);
    s.sync.start();
    return s;
  }

  Future<void> close() async {
    await live.close();
    await _http.close(force: true);
    store.close();
    _dir.deleteSync(recursive: true);
  }
}

/// Waits (real time) until [done] holds; fails after [limit].
Future<Duration> waitFor(
  bool Function() done, {
  Duration limit = const Duration(seconds: 20),
}) async {
  final watch = Stopwatch()..start();
  while (!done()) {
    if (watch.elapsed > limit) fail('not within $limit');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  return watch.elapsed;
}
