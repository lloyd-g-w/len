import 'dart:convert';

import '../data/syncable.dart';
import 'pull_page.dart';

/// What the server sends on a live connection (`/v1/live`,
/// docs/SYNC_PROTOCOL.md "Live connection"), parsed. Messages Len cannot
/// read are [LiveOther]: a sign of life all the same.
sealed class LiveMessage {
  const LiveMessage();

  /// Parses one text message.
  static LiveMessage parse(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return const LiveOther();
    }
    if (json is! Map<String, Object?>) return const LiveOther();
    return switch (json) {
      {'type': 'hello', 'serverId': final String serverId, 'seq': final int seq} => LiveHello(
        serverId: serverId,
        seq: seq,
        connection: json['connection'] as String? ?? '',
      ),
      {
        'type': 'records',
        'prevSeq': final int prevSeq,
        'seq': final int seq,
        'records': final List<Object?> records,
      }
          when prevSeq >= 0 && seq > prevSeq =>
        LiveRecords.parse(prevSeq, seq, records),
      {'type': 'resync'} => LiveResync(
        seq: json['seq'] as int? ?? 0,
        serverId: json['serverId'] as String?,
      ),
      {'type': 'pushed', 'serverSeq': final int serverSeq} => LivePushed(
        id: json['id'],
        applied: json['applied'] as int? ?? 0,
        serverSeq: serverSeq,
        stale: json['stale'] == true,
      ),
      {'type': 'error'} => LiveError(
        id: json['id'],
        status: json['status'] as int?,
        error: '${json['error']}',
        index: json['index'] as int?,
      ),
      {'type': 'presence', 'room': final String room, 'members': final List<Object?> members} =>
        LivePresence(room, [
          for (final m in members)
            if (m case {'connection': final String connection})
              (
                connection: connection,
                deviceId: m['deviceId'] as String?,
                name: m['name'] as String?,
              ),
        ]),
      {
        'type': 'ephemeral',
        'room': final String room,
        'from': final String from,
        'data': final Map<String, Object?> data,
      } =>
        LiveEphemeral(room: room, from: from, deviceId: json['deviceId'] as String?, data: data),
      _ => const LiveOther(),
    };
  }
}

/// The first message: the server's id and newest seq, and this
/// connection's id (as other members of a room see it).
final class LiveHello extends LiveMessage {
  const LiveHello({required this.serverId, required this.seq, required this.connection});
  final String serverId;
  final int seq;
  final String connection;
}

/// Records another device's push just stored: the feed entries after
/// [prevSeq] up to [seq] (records already parsed and prepared, see
/// [prepareRecord]; [malformed] of them dropped).
final class LiveRecords extends LiveMessage {
  const LiveRecords({
    required this.prevSeq,
    required this.seq,
    required this.records,
    this.malformed = 0,
  });

  factory LiveRecords.parse(int prevSeq, int seq, List<Object?> raw) {
    final records = <SyncRecord>[];
    var malformed = 0;
    for (final r in raw) {
      try {
        records.add(prepareRecord(SyncRecord.fromJson(r)));
      } on FormatException {
        malformed++;
      }
    }
    return LiveRecords(prevSeq: prevSeq, seq: seq, records: records, malformed: malformed);
  }

  final int prevSeq;
  final int seq;
  final List<SyncRecord> records;
  final int malformed;
}

/// The feed moved on in a way the connection did not carry (records too
/// large, a client that fell behind, a new server id): pull.
final class LiveResync extends LiveMessage {
  const LiveResync({required this.seq, this.serverId});
  final int seq;
  final String? serverId;
}

/// The answer to a `push`: [applied] records stored, the newest at
/// [serverSeq]; or [stale]: the client lacks changes up to [serverSeq].
final class LivePushed extends LiveMessage {
  const LivePushed({
    required this.id,
    required this.applied,
    required this.serverSeq,
    this.stale = false,
  });
  final Object? id;
  final int applied;
  final int serverSeq;
  final bool stale;
}

/// A request that failed ([status] as HTTP would say, if any).
final class LiveError extends LiveMessage {
  const LiveError({required this.id, required this.error, this.status, this.index});
  final Object? id;
  final int? status;
  final String error;
  final int? index;
}

/// Who is in [room] (this connection too).
final class LivePresence extends LiveMessage {
  const LivePresence(this.room, this.members);
  final String room;
  final List<LiveMember> members;
}

/// A member of a room.
typedef LiveMember = ({String connection, String? deviceId, String? name});

/// A message another member of [room] relayed (not stored).
final class LiveEphemeral extends LiveMessage {
  const LiveEphemeral({
    required this.room,
    required this.from,
    required this.deviceId,
    required this.data,
  });
  final String room;
  final String from;
  final String? deviceId;
  final Map<String, Object?> data;
}

/// A heartbeat, a pong, or a message Len does not know.
final class LiveOther extends LiveMessage {
  const LiveOther();
}
