/// Server configuration read from environment variables.
library;

import 'dart:io' show File;

import 'blob_api.dart' show defaultBlobIdleTimeout, defaultMaxBlobBytes;
import 'cors.dart';

/// Thrown when the environment does not describe a valid configuration.
class ConfigException implements Exception {
  ConfigException(this.message);

  final String message;

  @override
  String toString() => 'ConfigException: $message';
}

/// Runtime configuration of the sync server.
class Config {
  const Config({
    required this.token,
    required this.dbPath,
    required this.host,
    required this.port,
    required this.blobDir,
    this.blobMaxBytes = defaultMaxBlobBytes,
    this.blobIdleTimeout = defaultBlobIdleTimeout,
    this.cors = const CorsPolicy.any(),
  });

  /// Minimum accepted length of [token].
  static const minTokenLength = 16;

  /// Shared bearer token clients must present (`LEN_SYNC_TOKEN`).
  final String token;

  /// Path of the SQLite database file (`LEN_DB_PATH`).
  final String dbPath;

  /// Interface to bind to (`HOST`).
  final String host;

  /// TCP port to listen on (`PORT`).
  final int port;

  /// Directory holding uploaded blobs (`LEN_BLOB_DIR`, default `blobs/`
  /// next to the database file).
  final String blobDir;

  /// Maximum size of one blob upload in bytes (`LEN_BLOB_MAX_BYTES`).
  final int blobMaxBytes;

  /// Longest pause within a blob upload before it is abandoned
  /// (`LEN_BLOB_IDLE_TIMEOUT`, seconds).
  final Duration blobIdleTimeout;

  /// Origins allowed to call the API from a browser (`LEN_CORS_ORIGINS`):
  /// unset, empty or `*` allows any origin, `none` disables CORS, otherwise
  /// a comma-separated list of origins such as `https://len.example.com`.
  final CorsPolicy cors;

  /// Builds a [Config] from [env] (typically `Platform.environment`).
  ///
  /// Throws a [ConfigException] if the token is missing or too short, or if
  /// `PORT` is not a valid port number, `LEN_BLOB_MAX_BYTES` is not a
  /// positive integer, `LEN_BLOB_IDLE_TIMEOUT` is not a positive number of
  /// seconds, or `LEN_CORS_ORIGINS` is not a valid origin list.
  factory Config.fromEnvironment(Map<String, String> env) {
    final dbPath = dbPathFrom(env);
    return Config(
      token: _readToken(env['LEN_SYNC_TOKEN']),
      dbPath: dbPath,
      host: _nonEmpty(env['HOST']) ?? '0.0.0.0',
      port: _readPort(env['PORT']),
      blobDir: blobDirFrom(env),
      blobMaxBytes: _readBlobMaxBytes(env['LEN_BLOB_MAX_BYTES']),
      blobIdleTimeout: _readIdleTimeout(env['LEN_BLOB_IDLE_TIMEOUT']),
      cors: _readCorsOrigins(env['LEN_CORS_ORIGINS']),
    );
  }

  /// The database path from `LEN_DB_PATH` (default `/data/len.db`).
  static String dbPathFrom(Map<String, String> env) =>
      _nonEmpty(env['LEN_DB_PATH']) ?? '/data/len.db';

  /// The blob directory from `LEN_BLOB_DIR` (default `blobs/` next to the
  /// database).
  static String blobDirFrom(Map<String, String> env) =>
      _nonEmpty(env['LEN_BLOB_DIR']) ?? '${File(dbPathFrom(env)).parent.path}/blobs';

  static CorsPolicy _readCorsOrigins(String? raw) {
    final value = _nonEmpty(raw);
    if (value == null || value == '*') return const CorsPolicy.any();
    if (value.toLowerCase() == 'none') return const CorsPolicy.disabled();
    final origins = <String>[];
    for (final entry in value.split(',')) {
      final origin = entry.trim();
      if (origin.isEmpty) continue;
      if (!_isOrigin(origin)) {
        throw ConfigException(
          'LEN_CORS_ORIGINS must be "*", "none" or a comma-separated list of origins like '
          '"https://len.example.com" (no path or trailing slash), got "$origin".',
        );
      }
      origins.add(origin);
    }
    if (origins.isEmpty) {
      throw ConfigException('LEN_CORS_ORIGINS lists no origins, got "$raw".');
    }
    return CorsPolicy.allowList(origins);
  }

  /// Whether [value] is a serialized origin: `http(s)://host[:port]`.
  static bool _isOrigin(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        uri.path.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        value.startsWith('${uri.scheme}://');
  }

  static int _readBlobMaxBytes(String? raw) {
    final value = _nonEmpty(raw);
    if (value == null) return defaultMaxBlobBytes;
    final bytes = int.tryParse(value);
    if (bytes == null || bytes < 1) {
      throw ConfigException('LEN_BLOB_MAX_BYTES must be a positive integer, got "$raw".');
    }
    return bytes;
  }

  static Duration _readIdleTimeout(String? raw) {
    final value = _nonEmpty(raw);
    if (value == null) return defaultBlobIdleTimeout;
    final seconds = int.tryParse(value);
    if (seconds == null || seconds < 1) {
      throw ConfigException(
        'LEN_BLOB_IDLE_TIMEOUT must be a positive number of seconds, got "$raw".',
      );
    }
    return Duration(seconds: seconds);
  }

  static String _readToken(String? raw) {
    final token = raw?.trim() ?? '';
    if (token.isEmpty) {
      throw ConfigException('LEN_SYNC_TOKEN must be set.');
    }
    if (token.length < minTokenLength) {
      throw ConfigException('LEN_SYNC_TOKEN must be at least $minTokenLength characters long.');
    }
    return token;
  }

  static int _readPort(String? raw) {
    final value = _nonEmpty(raw);
    if (value == null) return 8080;
    final port = int.tryParse(value);
    if (port == null || port < 1 || port > 65535) {
      throw ConfigException('PORT must be an integer in 1..65535, got "$raw".');
    }
    return port;
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
