import 'package:web_socket_channel/io.dart';

import '../sync/live_channel.dart';
import '../sync/sync_api.dart';

/// Connects to [api]'s server's `/v1/live` with the token in a header.
Future<LiveChannel> connectLive(SyncApi api) => WebSocketLiveChannel.open(
  IOWebSocketChannel.connect(
    api.liveUri,
    headers: {'Authorization': 'Bearer ${api.token}'},
    connectTimeout: api.timeout,
  ),
  timeout: api.timeout,
);
