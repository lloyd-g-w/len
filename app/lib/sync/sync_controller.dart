import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/settings_repository.dart';
import 'blob_sync.dart';
import 'sync_api.dart';
import 'sync_engine.dart';

enum SyncState { disabled, idle, syncing, error }

/// Schedules sync cycles and exposes their status to the UI.
class SyncController extends ChangeNotifier {
  SyncController({
    required this.engine,
    required this.settings,
    this.interval = const Duration(seconds: 45),
    this.apiFactory = _defaultApi,
  }) {
    _state = isConfigured ? SyncState.idle : SyncState.disabled;
  }

  final SyncEngine engine;
  final SettingsRepository settings;
  final Duration interval;

  /// Creates the API client for one sync run; may throw [SyncException]
  /// for an invalid URL.
  final SyncApi Function(String url, String token) apiFactory;

  static SyncApi _defaultApi(String url, String token) =>
      SyncApi(baseUrl: url, token: token);

  final _remoteChanges = StreamController<RemoteChanges>.broadcast();
  Timer? _timer;
  Future<void>? _running;
  Future<void>? _queued;
  bool _disposed = false;

  /// Bumped whenever the configuration changes; a run started under an
  /// older configuration stops at its next checkpoint.
  int _configGeneration = 0;

  late SyncState _state;
  String? _lastError;
  DateTime? _lastSuccess;

  SyncState get state => _state;
  String? get lastError => _lastError;
  DateTime? get lastSuccess => _lastSuccess;

  bool get isConfigured => settings.syncUrl.isNotEmpty && settings.syncToken.isNotEmpty;

  /// Fires after a sync that changed local data.
  Stream<RemoteChanges> get remoteChanges => _remoteChanges.stream;

  /// Starts periodic syncing (and syncs once right away).
  void start() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(syncNow()));
    unawaited(syncNow());
  }

  /// Stores a new server configuration. Switching servers resets the change
  /// feed position and re-uploads everything, so the new server gets a
  /// complete copy. A sync already running is abandoned at its next
  /// checkpoint; call [syncNow] to sync with the new settings.
  void configure({required String url, required String token}) {
    final normalizedUrl = _normalizeUrl(url);
    final changedServer = normalizedUrl != _normalizeUrl(settings.syncUrl);
    settings
      ..syncUrl = normalizedUrl
      ..syncToken = token.trim();
    if (changedServer) engine.resetForNewServer();
    _configGeneration++;
    _setState(isConfigured ? SyncState.idle : SyncState.disabled);
  }

  /// Verifies a configuration without saving it. Throws [SyncException].
  Future<void> test({required String url, required String token}) async {
    final api = apiFactory(_normalizeUrl(url), token.trim());
    try {
      await api.check();
    } finally {
      api.close();
    }
  }

  /// Runs a sync now. If one is already running, a single follow-up run is
  /// queued (so changes made meanwhile are included) and the returned
  /// future completes after it.
  Future<void> syncNow() {
    if (_disposed) return Future.value();
    final running = _running;
    if (running == null) {
      return _running = _run().whenComplete(() => _running = null);
    }
    return _queued ??= running.then((_) {
      _queued = null;
      return syncNow();
    });
  }

  /// Downloads blob [sha] from the server if it is not stored locally.
  /// Returns whether it is available now; never throws (a missing blob is
  /// retried the next time it is needed).
  Future<bool> fetchBlob(String sha) async {
    final blobs = engine.blobs;
    if (blobs == null) return false;
    if (await blobs.has(sha)) return true;
    if (!isConfigured || _disposed) return false;
    SyncApi? api;
    try {
      api = apiFactory(settings.syncUrl, settings.syncToken);
      return await BlobSync(blobs).download(api, sha);
    } on SyncException catch (e) {
      debugPrint('Cannot fetch blob $sha: ${e.message}');
      return false;
    } finally {
      api?.close();
    }
  }


  Future<void> _run() async {
    if (!isConfigured) {
      _setState(SyncState.disabled);
      return;
    }
    final generation = _configGeneration;
    bool cancelled() => _disposed || generation != _configGeneration;

    _setState(SyncState.syncing);
    SyncApi? api;
    try {
      api = apiFactory(settings.syncUrl, settings.syncToken);
      final changes = await engine.sync(api, isCancelled: cancelled);
      if (cancelled()) return;
      _lastError = null;
      _lastSuccess = DateTime.now();
      _setState(SyncState.idle);
      if (!changes.isEmpty) _remoteChanges.add(changes);
    } on SyncException catch (e) {
      _fail(e.message, cancelled());
    } catch (e, stack) {
      // Unexpected (e.g. a database error): report it instead of leaving
      // the state stuck on "syncing" or crashing the periodic timer.
      debugPrint('Sync failed: $e\n$stack');
      _fail('Sync failed: $e', cancelled());
    } finally {
      api?.close();
    }
  }

  void _fail(String message, bool cancelled) {
    if (cancelled) return;
    _lastError = message;
    _setState(SyncState.error);
  }

  void _setState(SyncState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  static String _normalizeUrl(String url) {
    var normalized = url.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_remoteChanges.close());
    super.dispose();
  }
}
