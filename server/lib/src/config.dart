/// Server configuration read from environment variables.
library;

import 'dart:io' show File;

import 'blob_api.dart' show defaultMaxBlobBytes;

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

  /// Builds a [Config] from [env] (typically `Platform.environment`).
  ///
  /// Throws a [ConfigException] if the token is missing or too short, or if
  /// `PORT` is not a valid port number, or `LEN_BLOB_MAX_BYTES` is not a
  /// positive integer.
  factory Config.fromEnvironment(Map<String, String> env) {
    final dbPath = _nonEmpty(env['LEN_DB_PATH']) ?? '/data/len.db';
    return Config(
      token: _readToken(env['LEN_SYNC_TOKEN']),
      dbPath: dbPath,
      host: _nonEmpty(env['HOST']) ?? '0.0.0.0',
      port: _readPort(env['PORT']),
      blobDir: _nonEmpty(env['LEN_BLOB_DIR']) ?? '${File(dbPath).parent.path}/blobs',
      blobMaxBytes: _readBlobMaxBytes(env['LEN_BLOB_MAX_BYTES']),
    );
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
