import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// What kind of failure a [SyncException] reports.
enum SyncFailure {
  /// The server could not be reached (or did not answer in time).
  network,

  /// The server rejected the access token.
  auth,

  /// The server (or a proxy in front of it) refused a request as too large.
  tooLarge,

  /// The address does not lead to a Len sync server, or to one speaking
  /// another protocol version.
  incompatible,

  /// The server no longer has changes this device has seen (it was restored
  /// from a backup or replaced); everything must be uploaded again.
  historyLost,

  /// Anything else: an error status or an unexpected response.
  server,
}

/// Thrown for any failed sync request, with a user-presentable message
/// that says what to do about it.
class SyncException implements Exception {
  const SyncException(this.message, {this.kind = SyncFailure.server});
  final String message;
  final SyncFailure kind;

  @override
  String toString() => message;

  static const rejectedToken = SyncException(
    'The server rejected the access token — check that it matches LEN_SYNC_TOKEN',
    kind: SyncFailure.auth,
  );

  static const notLen = SyncException(
    'No Len sync server answers at this URL — check the address',
    kind: SyncFailure.incompatible,
  );

  static const serverTooOld = SyncException(
    'The sync server is too old for this version of Len — update the server',
    kind: SyncFailure.incompatible,
  );

  static const serverTooNew = SyncException(
    'The sync server is newer than this version of Len — update the app',
    kind: SyncFailure.incompatible,
  );

  static const historyLost = SyncException(
    'The sync server lost recent changes (restored or replaced)',
    kind: SyncFailure.historyLost,
  );

  static const unexpected = SyncException(
    'Unexpected response from the sync server — check the URL',
    kind: SyncFailure.incompatible,
  );

  /// A request that failed before any answer arrived ([error] is what the
  /// HTTP client threw), explained in words: raw socket errors say little
  /// to most people. The details go to the debug log.
  factory SyncException.unreachable(Object error) {
    debugPrint('Sync request failed: $error');
    final text = '$error';
    bool has(String s) => text.contains(s);
    final String message;
    if (error is TimeoutException) {
      message = 'The sync server did not answer in time — check your connection';
    } else if (has('Failed host lookup') || has('No address associated')) {
      message = 'Cannot find the sync server — check the URL and your connection';
    } else if (has('Connection refused')) {
      message = 'The sync server refused the connection — is it running?';
    } else if (has('CERTIFICATE') || has('Handshake') || has('TLS') || has('SSL')) {
      message = 'Secure connection to the sync server failed — check its HTTPS certificate';
    } else if (has('XMLHttpRequest') || (kIsWeb && error is! TimeoutException)) {
      // Browsers hide the reason; a missing CORS permission looks the same.
      message =
          'Cannot reach the sync server — check the URL, your connection and '
          'that the server allows this site (LEN_CORS_ORIGINS)';
    } else {
      message = 'Cannot reach the sync server — check the URL and your connection';
    }
    return SyncException(message, kind: SyncFailure.network);
  }

  /// The failure an unsuccessful HTTP [status] (with [body]) stands for.
  factory SyncException.status(int status, String body) => switch (status) {
    401 => rejectedToken,
    404 || 405 => notLen,
    409 => historyLost,
    413 => const SyncException(
      'The sync server refused an oversized request',
      kind: SyncFailure.tooLarge,
    ),
    502 || 503 || 504 => SyncException(
      'The sync server is not responding (error $status from a proxy) — is it running?',
      kind: SyncFailure.network,
    ),
    _ => SyncException('Sync server error $status${_errorDetail(decodeObject(body))}'),
  };

  /// The server's `{"error": "…"}` message, shortened; never raw bodies,
  /// which may be large HTML pages from a proxy.
  static String _errorDetail(Map<String, Object?>? json) {
    final error = json?['error'];
    if (error is! String || error.isEmpty) return '';
    return ': ${error.length > 200 ? '${error.substring(0, 200)}…' : error}';
  }
}

/// [body] as a JSON object, or null if it is not one.
Map<String, Object?>? decodeObject(String body) {
  try {
    final decoded = jsonDecode(body);
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}
