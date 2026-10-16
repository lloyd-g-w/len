import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'real_server.dart';

/// What can go wrong with one request (see [FaultyNetwork]).
enum Fault {
  /// The connection breaks before the server sees the request.
  dropBefore,

  /// The connection breaks while the request body is sent: the server sees
  /// part of it, then an error.
  dropMidRequest,

  /// The server handles the request, but its answer is lost.
  lostResponse,

  /// The answer breaks off half way.
  dropMidResponse,

  /// The answer is cut short without an error (a proxy closing early).
  truncated,

  /// A proxy answers 502, 503 or 504 without asking the server.
  gateway,

  /// The server handles the request, then a proxy answers 504 anyway.
  gatewayAfter,

  /// A proxy or the server answers 500 without handling the request.
  serverError,

  /// Too many requests (429) without handling the request.
  tooMany,

  /// The request is sent twice (a retry after a lost answer); the second
  /// answer arrives.
  duplicate,

  /// The server restarts before the request.
  restart,

  /// The app is killed while the request is in flight (see
  /// [FaultyNetwork.clientFor]'s `onKill`).
  kill,
}

/// A network between devices and a [RealServer] that delays, drops,
/// duplicates, truncates and fails requests at random (seeded), and
/// restarts the server or kills the app now and then.
class FaultyNetwork {
  FaultyNetwork(this.server, this.random);

  final RealServer server;
  final math.Random random;

  /// Chance of a fault per request (0: a clean network).
  double rate = 0;

  /// Faults to pick from (each equally likely) when one happens.
  List<Fault> faults = Fault.values;

  /// How often each fault happened.
  final Map<Fault, int> counts = {};

  /// Requests sent through the network.
  int requests = 0;

  /// A client for one app run. [onKill] kills the app (closing its
  /// database); once [killed] says so, every request of this client fails,
  /// as no app is left to send it.
  http.Client clientFor({void Function()? onKill, bool Function()? killed}) =>
      _FaultyClient(this, onKill, killed ?? () => false);

  Fault? _pick({required bool canKill}) {
    if (rate == 0 || random.nextDouble() >= rate) return null;
    final choices = canKill
        ? faults
        : [
            for (final f in faults)
              if (f != Fault.kill) f,
          ];
    if (choices.isEmpty) return null;
    final fault = choices[random.nextInt(choices.length)];
    counts.update(fault, (n) => n + 1, ifAbsent: () => 1);
    return fault;
  }

  Future<void> _latency() async {
    // Mostly none, sometimes a few milliseconds: reorders what runs
    // concurrently (a page fetched ahead while one is applied, edits).
    final roll = random.nextInt(10);
    if (roll < 6) return;
    await Future<void>.delayed(Duration(microseconds: roll < 9 ? 0 : random.nextInt(3000)));
  }
}

class _FaultyClient extends http.BaseClient {
  _FaultyClient(this.network, this.onKill, this.killed);

  final FaultyNetwork network;
  final void Function()? onKill;
  final bool Function() killed;

  math.Random get _r => network.random;

  RealServer get _server => network.server;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    network.requests++;
    await network._latency();
    if (killed()) throw http.ClientException('the app was killed', request.url);
    final response = await _send(request);
    // No app is left to read the answer.
    if (killed()) throw http.ClientException('the app was killed', request.url);
    return response;
  }

  Future<http.StreamedResponse> _send(http.BaseRequest request) async {
    final fault = network._pick(canKill: onKill != null);
    switch (fault) {
      case null:
        return _forward(request);
      case Fault.dropBefore:
        await request.finalize().drain<void>().catchError((_) {});
        throw http.ClientException('Connection reset (before sending)', request.url);
      case Fault.dropMidRequest:
        final bytes = await _bytes(request.finalize());
        final cut = bytes.isEmpty ? 0 : _r.nextInt(bytes.length);
        final body = StreamController<List<int>>();
        body.add(bytes.sublist(0, cut));
        body.addError(http.ClientException('Connection reset by peer', request.url));
        unawaited(body.close());
        try {
          final answer = await _server.handle(request, body: body.stream);
          await answer.stream.drain<void>().catchError((_) {});
        } on Object {
          // The server failing on the broken body is fine.
        }
        throw http.ClientException('Connection reset (while sending)', request.url);
      case Fault.lostResponse:
        final answer = await _forward(request);
        await answer.stream.drain<void>().catchError((_) {});
        throw http.ClientException('Connection reset (answer lost)', request.url);
      case Fault.dropMidResponse:
        final answer = await _forward(request);
        final bytes = await _bytes(answer.stream);
        final out = StreamController<List<int>>();
        if (bytes.isNotEmpty) out.add(bytes.sublist(0, _r.nextInt(bytes.length)));
        out.addError(http.ClientException('Connection closed while receiving data', request.url));
        unawaited(out.close());
        return _like(answer, out.stream, request, length: bytes.length);
      case Fault.truncated:
        final answer = await _forward(request);
        final bytes = await _bytes(answer.stream);
        final cut = bytes.isEmpty ? 0 : _r.nextInt(bytes.length);
        return _like(answer, Stream.value(bytes.sublist(0, cut)), request);
      case Fault.gateway:
        await request.finalize().drain<void>().catchError((_) {});
        return _status(request, 502 + _r.nextInt(3), '<html>Bad gateway</html>');
      case Fault.gatewayAfter:
        final answer = await _forward(request);
        await answer.stream.drain<void>().catchError((_) {});
        return _status(request, 504, '<html>Gateway timeout</html>');
      case Fault.serverError:
        await request.finalize().drain<void>().catchError((_) {});
        return _status(request, 500, '{"error":"internal server error"}');
      case Fault.tooMany:
        await request.finalize().drain<void>().catchError((_) {});
        return _status(request, 429, '{"error":"slow down"}', retryAfter: true);
      case Fault.duplicate:
        final bytes = await _bytes(request.finalize());
        final first = await _server.handle(request, body: Stream.value(bytes));
        await first.stream.drain<void>().catchError((_) {});
        await network._latency();
        return _server.handle(request, body: Stream.value(bytes));
      case Fault.restart:
        _server.restart();
        return _forward(request);
      case Fault.kill:
        // The request may or may not have reached the server.
        if (_r.nextBool()) {
          final answer = await _forward(request);
          await answer.stream.drain<void>().catchError((_) {});
        } else {
          await request.finalize().drain<void>().catchError((_) {});
        }
        onKill?.call();
        throw http.ClientException('the app was killed', request.url);
    }
  }

  Future<http.StreamedResponse> _forward(http.BaseRequest request) => _server.handle(request);

  static Future<Uint8List> _bytes(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    await stream.forEach(builder.add);
    return builder.takeBytes();
  }

  static http.StreamedResponse _like(
    http.StreamedResponse answer,
    Stream<List<int>> body,
    http.BaseRequest request, {
    int? length,
  }) => http.StreamedResponse(
    body,
    answer.statusCode,
    contentLength: length,
    headers: {...answer.headers}..remove('content-length'),
    request: request,
  );

  static http.StreamedResponse _status(
    http.BaseRequest request,
    int status,
    String body, {
    bool retryAfter = false,
  }) => http.StreamedResponse(
    Stream.value(Uint8List.fromList(body.codeUnits)),
    status,
    headers: {'content-type': 'text/plain', if (retryAfter) 'retry-after': '1'},
    request: request,
  );
}
