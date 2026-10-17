import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

/// The transport of a live connection (`/v1/live`): text messages both
/// ways. [messages] ends (or fails) when the connection does.
abstract interface class LiveChannel {
  Stream<String> get messages;

  void send(String message);

  /// Closes the connection (nothing more is heard).
  void close();
}

/// A [LiveChannel] over a WebSocket (every platform).
class WebSocketLiveChannel implements LiveChannel {
  WebSocketLiveChannel._(this._channel);

  /// Waits until [channel] is connected; throws if it cannot be.
  static Future<LiveChannel> open(WebSocketChannel channel, {required Duration timeout}) async {
    try {
      await channel.ready.timeout(timeout);
    } on Object {
      unawaited(channel.sink.close().catchError((Object _) {}));
      rethrow;
    }
    return WebSocketLiveChannel._(channel);
  }

  final WebSocketChannel _channel;

  @override
  Stream<String> get messages => _channel.stream.where((m) => m is String).cast<String>();

  @override
  void send(String message) => _channel.sink.add(message);

  @override
  void close() => unawaited(_channel.sink.close().catchError((Object _) {}));
}
