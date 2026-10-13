import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A small store for secrets (the sync access token) kept by the
/// platform: the Android Keystore, the desktop's Secret Service keyring
/// on Linux (libsecret), DPAPI / Credential Manager on Windows.
///
/// Every call may throw when the store is unavailable (no keyring in a
/// Linux session, a locked keyring, a Keystore error): callers keep the
/// secret elsewhere and try again later (`SyncTokenStore`).
abstract interface class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// The platform's secure store, or null in a browser: nothing there is
/// secret from scripts of the same origin (an encrypted entry would sit
/// next to its key), so the token stays in Len's own storage (IndexedDB).
SecureStore? platformSecureStore() => kIsWeb ? null : _PluginSecureStore();

/// [SecureStore] over `flutter_secure_storage`.
class _PluginSecureStore implements SecureStore {
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// A [SecureStore] in memory (tests, and services created without one);
/// throws while not [available], like a missing or locked keyring.
class MemorySecureStore implements SecureStore {
  /// The stored secrets by key.
  final Map<String, String> values = {};

  /// Whether calls succeed.
  bool available = true;

  void _check() {
    if (!available) throw StateError('secure store unavailable');
  }

  @override
  Future<String?> read(String key) async {
    _check();
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    _check();
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _check();
    values.remove(key);
  }
}
