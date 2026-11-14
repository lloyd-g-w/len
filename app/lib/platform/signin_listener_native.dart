import 'dart:async';
import 'dart:io';

import 'signin_listener_api.dart';

export 'signin_listener_api.dart';

/// [SigninListener] on 127.0.0.1 for the sign-in page's redirect: each
/// `GET /callback?…` is answered with a page saying to go back to Len,
/// and its URL is in [callbacks].
class _LoopbackListener implements SigninListener {
  _LoopbackListener(this._server) {
    _server.listen(_handle, onError: (Object _) {});
  }

  final HttpServer _server;
  final _callbacks = StreamController<String>.broadcast();

  @override
  int get port => _server.port;

  @override
  Stream<String> get callbacks => _callbacks.stream;

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    if (request.method != 'GET' || request.uri.path != '/callback') {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final cancelled = request.uri.queryParameters.containsKey('error');
    response
      ..headers.contentType = ContentType.html
      ..headers.set('cache-control', 'no-store')
      ..headers.set('referrer-policy', 'no-referrer')
      ..write(
        '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<title>Len</title><style>body{font:16px/1.5 system-ui,sans-serif;'
        'padding:48px 16px;max-width:28rem;margin:auto}</style></head><body>'
        '<h1>${cancelled ? 'Cancelled' : 'Back to Len'}</h1><p>'
        '${cancelled ? 'Nothing was sent to Len.' : 'Len is finishing signing in.'} '
        'You can close this tab.</p></body></html>',
      );
    await response.close();
    if (!_callbacks.isClosed) _callbacks.add(request.requestedUri.toString());
  }

  @override
  Future<void> close() async {
    await _server.close(force: true);
    await _callbacks.close();
  }
}

/// Starts a listener on a free port of 127.0.0.1.
Future<SigninListener?> startSigninListener() async =>
    _LoopbackListener(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
