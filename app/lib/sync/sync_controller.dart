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
    _refreshTooLarge();
  }

  final SyncEngine engine;
  final SettingsRepository settings;
  final Duration interval;

  /// Creates the API client for one sync run; may throw [SyncException]
  /// for an invalid URL.
  final SyncApi Function(String url, String token) apiFactory;

  static SyncApi _defaultApi(String url, String token) => SyncApi(baseUrl: url, token: token);

  final _remoteChanges = StreamController<RemoteChanges>.broadcast();
  final _notices = StreamController<String>.broadcast();
  Timer? _timer;
  Future<void>? _running;
  Future<void>? _queued;
  bool _disposed = false;

  /// Bumped whenever the configuration changes; a run started under an
  /// older configuration stops at its next checkpoint.
  int _configGeneration = 0;

  late SyncState _state;
  String? _lastError;
  String? _lastErrorDetails;
  SyncFailure? _lastFailure;
  DateTime? _lastSuccess;

  SyncState get state => _state;

  /// What went wrong in the last sync, in plain words (null after a
  /// successful one).
  String? get lastError => _lastError;

  /// Technical detail behind [lastError], for "Details" (the exception's
  /// text), when there is more to say than the message.
  String? get lastErrorDetails => _lastErrorDetails;

  /// The kind of the last failure, if the last sync failed.
  SyncFailure? get lastFailure => _state == SyncState.error ? _lastFailure : null;

  /// Whether automatic syncs wait for the user: the server refused the
  /// access token, which retrying cannot fix. Saving settings (or "Sync
  /// now") tries again.
  bool get waitsForSettings => lastFailure == SyncFailure.auth;
  DateTime? get lastSuccess => _lastSuccess;

  List<({String sha, int size})> _tooLarge = const [];

  /// Local files (blobs) the server refuses as too large: they stay on this
  /// device, records referencing them sync without them.
  List<({String sha, int size})> get tooLargeFiles => _tooLarge;

  /// "1 file too large to sync", or null if there is none.
  String? get tooLargeSummary =>
      _tooLarge.isEmpty ? null : '${_files(_tooLarge.length)} too large to sync';

  /// The server's blob size limit as last reported, if known.
  int? get serverMaxBlobBytes => engine.serverInfo?.maxBlobBytes;

  /// Tries uploading the [tooLargeFiles] again (e.g. after the server's
  /// limit was raised) and syncs.
  Future<void> retryTooLargeFiles() {
    engine.blobs?.retryTooLarge();
    _refreshTooLarge();
    notifyListeners();
    return syncNow();
  }

  void _refreshTooLarge() => _tooLarge = engine.blobs?.tooLarge() ?? const [];

  bool get isConfigured => settings.syncUrl.isNotEmpty && settings.syncToken.isNotEmpty;

  /// Fires after a sync that changed local data.
  Stream<RemoteChanges> get remoteChanges => _remoteChanges.stream;

  /// One-line notices for the user (e.g. everything was synced again
  /// because the server changed), each sent once after the sync it concerns.
  Stream<String> get notices => _notices.stream;

  /// Announces [changes] as if a sync had brought them (tests).
  @visibleForTesting
  void debugAnnounce(RemoteChanges changes) => _remoteChanges.add(changes);

  /// Starts periodic syncing (and syncs once right away).
  void start() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(syncInBackground()));
    unawaited(syncNow());
  }

  /// A sync nobody asked for (the timer, leaving or returning to the app):
  /// skipped while [waitsForSettings].
  Future<void> syncInBackground() => waitsForSettings ? Future.value() : syncNow();

  /// Stores a new server configuration. A sync already running is
  /// abandoned at its next checkpoint; call [syncNow] to sync with the new
  /// settings. Whether this is another server is told by its id at the next
  /// sync ([SyncEngine.sync]): then the change feed position is reset and
  /// everything uploaded, so the new server gets a complete copy, while a
  /// new address of the same server (or a new token) changes nothing.
  void configure({required String url, required String token}) {
    settings
      ..syncUrl = _normalizeUrl(url)
      ..syncToken = token.trim();
    _configGeneration++;
    _lastError = _lastErrorDetails = _lastFailure = null;
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
      _refreshTooLarge();
      _lastSuccess = DateTime.now();
      final failed = engine.failedBlobUploads;
      if (failed == 0) {
        _lastError = _lastErrorDetails = _lastFailure = null;
        _setState(SyncState.idle);
      } else {
        // Everything else synced; the files are retried next time.
        _fail(
          '${_files(failed)} could not be uploaded and will be retried',
          false,
          details: engine.blobUploadError,
        );
      }
      if (!changes.isEmpty) _remoteChanges.add(changes);
      if (engine.takeResync() case final notice?) _notices.add(notice);
    } on SyncException catch (e) {
      _fail(e.message, cancelled(), kind: e.kind);
    } catch (e, stack) {
      // Unexpected (e.g. a database error): report it instead of leaving
      // the state stuck on "syncing" or crashing the periodic timer.
      debugPrint('Sync failed: $e\n$stack');
      _fail(
        'Something went wrong on this device while syncing; it will try again',
        cancelled(),
        details: '$e',
      );
    } finally {
      api?.close();
    }
  }

  static String _files(int n) => n == 1 ? '1 file' : '$n files';

  void _fail(
    String message,
    bool cancelled, {
    SyncFailure kind = SyncFailure.server,
    String? details,
  }) {
    if (cancelled) return;
    _refreshTooLarge();
    _lastError = message;
    _lastErrorDetails = details;
    _lastFailure = kind;
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
    unawaited(_notices.close());
    super.dispose();
  }
}
