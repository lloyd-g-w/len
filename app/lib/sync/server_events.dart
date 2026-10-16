import 'dart:async';
import 'dart:convert';

/// What the server's event stream (`/v1/events`) says: its change feed
/// reached [seq] on the server with id [serverId].
typedef ServerEvent = ({int seq, String serverId});

/// Parses a Server-Sent Events body (docs/SYNC_PROTOCOL.md, `/v1/events`)
/// into [ServerEvent]s, with `null` for every comment (the server's
/// heartbeats) and for events that are not one (ignored: any sign of life
/// counts). Lines may end in CR LF, LF or CR.
Stream<ServerEvent?> parseServerEvents(Stream<List<int>> bytes) {
  // (No async*: cancelling one only takes effect at its next event, a
  // heartbeat away; transformers pass it on to the connection at once.)
  final data = <String>[];
  var sawComment = false;
  return bytes
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .transform(
        StreamTransformer<String, ServerEvent?>.fromHandlers(
          handleData: (line, sink) {
            if (line.isEmpty) {
              if (data.isNotEmpty) {
                sink.add(_event(data.join('\n')));
                data.clear();
              } else if (sawComment) {
                sink.add(null);
              }
              sawComment = false;
            } else if (line.startsWith(':')) {
              sawComment = true;
            } else if (line == 'data' || line.startsWith('data:')) {
              final value = line.length > 5 ? line.substring(5) : '';
              data.add(value.startsWith(' ') ? value.substring(1) : value);
            }
            // Other fields (event, id, retry) say nothing Len needs.
          },
        ),
      );
}

ServerEvent? _event(String data) {
  try {
    if (jsonDecode(data) case {'seq': final int seq, 'serverId': final String serverId}
        when seq >= 0) {
      return (seq: seq, serverId: serverId);
    }
  } on FormatException {
    // Not an event Len knows: a sign of life all the same.
  }
  return null;
}
