import 'package:web_socket_channel/web_socket_channel.dart';

import '../sync/live_channel.dart';
import '../sync/sync_api.dart';

/// Connects to [api]'s server's `/v1/live` with a one-time ticket.
Future<LiveChannel> connectLive(SyncApi api) async {
  final ticket = await api.liveTicket();
  return WebSocketLiveChannel.open(
    WebSocketChannel.connect(api.liveUri.replace(queryParameters: {'ticket': ticket})),
    timeout: api.timeout,
  );
}
