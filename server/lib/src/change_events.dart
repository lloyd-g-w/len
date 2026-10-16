/// `GET /v1/events`: Server-Sent Events telling clients the feed moved on.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpStatus;

import 'package:shelf/shelf.dart';

/// How often an idle event stream carries a heartbeat comment: often
/// enough for proxies (nginx: 60 s read timeout) and NATs to keep the
/// connection, and for clients to notice a dead one.
const defaultEventHeartbeat = Duration(seconds: 20);

/// Default limit of event streams open at once.
const defaultMaxEventStreams = 1000;

/// Open event streams and what they are sent: the newest seq (and the
/// server's id) when a stream opens and whenever a push stored something.
class ChangeEvents {
  ChangeEvents({this.heartbeat = defaultEventHeartbeat, this.maxStreams = defaultMaxEventStreams});

  /// Interval of the heartbeat comments (`: ping`).
  final Duration heartbeat;

  /// Streams beyond this many are answered `503`.
  final int maxStreams;

  final Set<_Stream> _streams = {};
  bool _closed = false;

  /// Number of open event streams.
  int get streams => _streams.length;

  /// Opens an event stream starting with [seq] and [serverId].
  Response subscribe({required int seq, required String serverId}) {
    if (_closed || _streams.length >= maxStreams) {
      return Response(
        HttpStatus.serviceUnavailable,
        body: jsonEncode({'error': 'too many event streams'}),
        headers: {'content-type': 'application/json; charset=utf-8', 'retry-after': '60'},
      );
    }
    late final _Stream stream;
    stream = _Stream(heartbeat, onDone: () => _streams.remove(stream));
    _streams.add(stream);
    stream.send(seq, serverId);
    return Response.ok(
      stream.controller.stream,
      headers: {
        'content-type': 'text/event-stream; charset=utf-8',
        // Proxies and caches must pass each event on as it comes:
        // `no-transform` keeps compressing proxies out, `X-Accel-Buffering`
        // turns nginx's response buffering off for this response.
        'cache-control': 'no-cache, no-store, no-transform',
        'x-accel-buffering': 'no',
      },
      // shelf_io: write every chunk at once instead of buffering it.
      context: {'shelf.io.buffer_output': false},
    );
  }

  /// Tells every open stream that the feed reached [seq] (on [serverId]).
  void publish({required int seq, required String serverId}) {
    for (final stream in _streams.toList()) {
      stream.send(seq, serverId);
    }
  }

  /// Ends every stream and refuses new ones (shutdown: open streams would
  /// otherwise keep the server's connections busy until forced closed).
  Future<void> close() async {
    _closed = true;
    await Future.wait([for (final stream in _streams.toList()) stream.close()]);
  }
}

/// One client's event stream.
class _Stream {
  _Stream(Duration heartbeat, {required void Function() onDone}) {
    controller = StreamController<List<int>>(
      onListen: () => _timer = Timer.periodic(heartbeat, (_) => _add(': ping\n\n')),
      onCancel: () {
        _timer?.cancel();
        onDone();
      },
    );
    _onDone = onDone;
  }

  late final StreamController<List<int>> controller;
  late final void Function() _onDone;
  Timer? _timer;

  /// Sends an event: the feed reached [seq] on server [serverId].
  void send(int seq, String serverId) =>
      _add('data: ${jsonEncode({'seq': seq, 'serverId': serverId})}\n\n');

  void _add(String text) {
    if (!controller.isClosed) controller.add(utf8.encode(text));
  }

  Future<void> close() async {
    _timer?.cancel();
    _onDone();
    if (!controller.isClosed) {
      // Not awaited: done only completes once a listener took the events.
      unawaited(controller.close());
    }
  }
}
