/// Routes of live connections: `GET /v1/live` (the WebSocket) and
/// `POST /v1/live/ticket` (a one-time ticket for browsers).
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

import 'cors.dart';
import 'live_hub.dart';
import 'live_tickets.dart';

/// How often the server pings a live connection at the WebSocket level
/// (a client that stops answering is dropped).
const livePingInterval = Duration(seconds: 30);

/// `POST /v1/live/ticket` (behind the bearer token): a ticket that opens
/// one live connection within [LiveTickets.lifetime].
Response issueTicket(LiveTickets tickets) => Response.ok(
  jsonEncode({'ticket': tickets.issue(), 'expiresIn': tickets.lifetime.inSeconds}),
  headers: {'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store'},
);

/// `GET /v1/live`: checks the bearer token (or a ticket from
/// [issueTicket]), the connection limit and the handshake, then upgrades
/// the connection to a WebSocket handed to [hub].
Response upgradeLive(
  Request request, {
  required LiveHub hub,
  required LiveTickets tickets,
  required bool Function(String? authorization) authorized,
  required CorsPolicy cors,
}) {
  final ticket = request.url.queryParameters['ticket'];
  final ok = ticket != null ? tickets.redeem(ticket) : authorized(request.headers['authorization']);
  if (!ok) return _json(HttpStatus.unauthorized, {'error': 'unauthorized'});
  // Browsers always send their origin on a WebSocket: with an allow-list,
  // only those origins (tickets already keep other sites out).
  final origin = request.headers['origin'];
  if (origin != null && cors.origins != null && cors.allowOriginFor(origin) == null) {
    return _json(HttpStatus.forbidden, {'error': 'origin not allowed'});
  }
  if (!hub.acceptsMore) {
    return Response(
      HttpStatus.serviceUnavailable,
      body: jsonEncode({'error': 'too many live connections'}),
      headers: {'content-type': 'application/json; charset=utf-8', 'retry-after': '60'},
    );
  }
  final key = request.headers['sec-websocket-key'];
  final upgrade = request.headers['upgrade']?.toLowerCase();
  final connection = request.headers['connection']?.toLowerCase() ?? '';
  if (request.method != 'GET' ||
      upgrade != 'websocket' ||
      !connection.split(',').map((t) => t.trim()).contains('upgrade') ||
      request.headers['sec-websocket-version'] != '13' ||
      key == null) {
    return _json(HttpStatus.upgradeRequired, {'error': 'WebSocket upgrade required'});
  }
  if (!request.canHijack) {
    return _json(HttpStatus.notImplemented, {'error': 'live connections need a socket'});
  }
  // (Not package:shelf_web_socket: it wraps the socket in a channel that
  // writes without backpressure, and the hub needs to see clients that do
  // not keep up, see LiveConnection.)
  request.hijack((channel) {
    final socket = channel.sink as Socket;
    socket.add(
      utf8.encode(
        'HTTP/1.1 101 Switching Protocols\r\n'
        'Upgrade: websocket\r\n'
        'Connection: Upgrade\r\n'
        'Sec-WebSocket-Accept: ${_accept(key)}\r\n\r\n',
      ),
    );
    final webSocket = WebSocket.fromUpgradedSocket(socket, serverSide: true)
      ..pingInterval = livePingInterval;
    hub.accept(LivePeer.webSocket(webSocket, destroy: socket.destroy));
  });
}

/// `Sec-WebSocket-Accept` for [key] (RFC 6455).
String _accept(String key) =>
    base64.encode(sha1.convert(utf8.encode('${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11')).bytes);

Response _json(int status, Object body) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json; charset=utf-8'},
);
