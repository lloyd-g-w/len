import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'browser_storage_api.dart';

export 'browser_storage_api.dart';

/// `navigator.storage`, or null in browsers without the Storage API (or on
/// insecure origins, where it is hidden).
BrowserStorage? get browserStorage =>
    (web.window.navigator as JSObject).has('storage') ? const _WebStorage() : null;

/// Asks once per start for persistent storage where that is silent
/// (Chromium, Safari: granted by engagement, e.g. an installed app). Firefox
/// would show a permission prompt at launch, so there the request waits for
/// the button in Settings → Storage.
Future<void> requestPersistentStorageOnStartup() async {
  final storage = browserStorage;
  if (storage == null || web.window.navigator.userAgent.contains('Firefox')) return;
  try {
    if (!await storage.isPersisted()) await storage.requestPersistence();
  } on Object catch (e) {
    debugPrint('Persistent storage request failed: $e');
  }
}

class _WebStorage implements BrowserStorage {
  const _WebStorage();

  web.StorageManager get _manager => web.window.navigator.storage;

  @override
  Future<bool> isPersisted() async => (await _manager.persisted().toDart).toDart;

  @override
  Future<bool> requestPersistence() async => (await _manager.persist().toDart).toDart;

  @override
  Future<StorageUsage?> usage() async {
    try {
      final estimate = await _manager.estimate().toDart;
      return (usage: estimate.usage, quota: estimate.quota);
    } on Object {
      return null;
    }
  }
}
