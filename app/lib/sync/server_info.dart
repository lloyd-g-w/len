import 'sync_errors.dart';

/// What `GET /v1/health` reports.
class ServerInfo {
  const ServerInfo({
    required this.serverId,
    required this.maxBlobBytes,
    required this.blobsCollectedAt,
  });

  /// The protocol version this app speaks.
  static const protocol = 1;

  /// Identifies the server's change history; a new id means another server
  /// (or one restored from a backup).
  final String serverId;

  /// Largest blob the server accepts.
  final int maxBlobBytes;

  /// When the server last deleted blobs by garbage collection (0 = never).
  final int blobsCollectedAt;

  /// Parses a health answer; throws [SyncException] when it is not one of a
  /// Len sync server speaking [protocol].
  factory ServerInfo.fromJson(Map<String, Object?>? json) {
    if (json == null || json['status'] != 'ok') throw SyncException.notLen;
    final version = json['protocol'];
    if (version is! int) throw SyncException.notLen;
    if (version > protocol) throw SyncException.serverTooNew;
    final (id, max, collected) = (json['serverId'], json['maxBlobBytes'], json['blobsCollectedAt']);
    if (version < protocol || id is! String || id.isEmpty || max is! int || collected is! int) {
      throw SyncException.serverTooOld;
    }
    if (max <= 0 || collected < 0) throw SyncException.unexpected;
    return ServerInfo(serverId: id, maxBlobBytes: max, blobsCollectedAt: collected);
  }
}
