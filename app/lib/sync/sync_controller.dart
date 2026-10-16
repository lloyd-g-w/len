import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/clock.dart';
import '../data/settings_repository.dart';
import '../data/sync_token_store.dart';
import 'blob_sync.dart';
import 'freed_files.dart';
import 'revival_notice.dart';
import 'sync_api.dart';
import 'sync_engine.dart';

part 'sync_controller_requests.dart';
part 'sync_controller_run.dart';

enum SyncState { disabled, idle, syncing, error }

/// Schedules sync cycles and exposes their status to the UI.
class SyncController extends ChangeNotifier with _SyncRequests {
  SyncController({
    required this.engine,
    required this.settings,
    required this.tokens,
    this.interval = const Duration(seconds: 45),
    this.apiFactory = _defaultApi,
    this.clock = const Clock(),
  }) {
    _state = isConfigured ? SyncState.idle : SyncState.disabled;
    if (settings.syncLastSuccess case final ms?) {
      _lastSuccess = DateTime.fromMillisecondsSinceEpoch(ms);
    }
    _refreshTooLarge();
    tokens.addListener(_tokenChanged);
    engine.onPullProgress = _onPullProgress;
  }

  @override
  final SyncEngine engine;
  @override
  final SettingsRepository settings;

  /// The access token (in the secure store, see [SyncTokenStore]).
  @override
  final SyncTokenStore tokens;
  final Duration interval;

  /// The app's clock: when syncs worked or began failing, and how long ago
  /// that is (the captions and alerts read it too).
  final Clock clock;

  /// Creates the API client for one sync run; may throw [SyncException]
  /// for an invalid URL.
  @override
  final SyncApi Function(String url, String token) apiFactory;

  static SyncApi _defaultApi(String url, String token) => SyncApi(baseUrl: url, token: token);

  final _remoteChanges = StreamController<RemoteChanges>.broadcast();
  @override
  final _notices = StreamController<String>.broadcast();
  Timer? _timer;
  Future<void>? _running;
  Future<void>? _queued;
  @override
  bool _disposed = false;

  /// The client of the run under way: closed when the configuration
  /// changes, so a request stuck on the old server (a long upload, a dead
  /// connection) does not hold up the next run until it times out.
  SyncApi? _api;

  /// Bumped whenever the configuration changes; a run started under an
  /// older configuration stops at its next checkpoint.
  @override
  int _configGeneration = 0;

  late SyncState _state;
  String? _lastError;
  String? _lastErrorDetails;
  SyncFailure? _lastFailure;
  DateTime? _lastSuccess;
  DateTime? _failingSince;
  int _filesNotUploaded = 0;

  SyncState get state => _state;

  /// How far a long pull is (0..1) while [state] is syncing, once it is
  /// more than a page (a new device's first sync, a long catch-up); null
  /// otherwise (UX_AUDIT R16-5).
  double? get progress => _progress;
  double? _progress;

  /// When the library last heard of notebooks and folders a long pull
  /// brought ([_onPullProgress]), and how many it had been brought then
  /// ([RemoteChanges.libraryWrites]).
  int _announcedAt = 0;
  int _announcedWrites = 0;

  /// How often a long pull tells the library about the notebooks and
  /// folders it brought so far, so a new device's library fills in while
  /// the rest arrives.
  static const Duration announceEvery = Duration(seconds: 2);

  void _onPullProgress(PullProgress p) {
    if (_disposed || _state != SyncState.syncing) return;
    _pullFrom = p.from;
    var progress = p.total <= 0 ? null : (p.done / p.total).clamp(0.0, 1.0);
    // The feed grows while another device pushes: the share pulled may
    // shrink, but the bar must not run back within a run.
    if (progress != null && _progress != null && progress < _progress!) progress = _progress;
    final percent = progress == null ? null : (progress * 100).floor();
    if (percent != (_progress == null ? null : (_progress! * 100).floor())) {
      _progress = progress;
      notifyListeners();
    }
    // The library reloads only for notebooks or folders it hasn't heard of
    // (pages of strokes alone change nothing there).
    final now = clock.nowMs();
    final writes = p.changes.libraryWrites;
    if (writes != _announcedWrites && now - _announcedAt >= announceEvery.inMilliseconds) {
      _announcedAt = now;
      _announcedWrites = writes;
      _remoteChanges.add(
        RemoteChanges()
          ..notebooks = p.changes.notebooks
          ..folders = p.changes.folders,
      );
    }
  }

  /// Files that couldn't be uploaded when the rest of the last sync worked
  /// (retried next time); 0 unless that is all that failed.
  int get filesNotUploaded => _state == SyncState.error ? _filesNotUploaded : 0;

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

  /// Whether this is the first sync with a server, under way: nothing of
  /// the other devices' notes may be here yet.
  /// (The feed position moves on with every page pulled: whether this is
  /// the first is told by where the pull began.)
  bool get firstSyncUnderWay =>
      _state == SyncState.syncing && (settings.syncLastSeq == 0 || _pullFrom == 0);

  /// Where the pull under way began in the server's feed, once it told.
  int? _pullFrom;

  /// When sync last succeeded (kept across launches), or null if never.
  DateTime? get lastSuccess => _lastSuccess;

  /// When syncs began failing, through the retries since (null while they
  /// work, and while sync is off).
  DateTime? get failingSince => _failingSince;

  /// Whether sync has failed for at least [after] (or waits for the
  /// settings): worth a quiet mark outside Settings (UX_AUDIT R7-14).
  bool failingFor(Duration after, {DateTime? now}) {
    if (waitsForSettings) return true;
    final since = _failingSince;
    return since != null && (now ?? clock.nowDate()).difference(since) >= after;
  }

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

  @override
  bool get isConfigured => settings.syncUrl.isNotEmpty && tokens.token.isNotEmpty;

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
    settings.syncUrl = _normalizeUrl(url);
    unawaited(tokens.save(token.trim()));
    _configGeneration++;
    _api?.close();
    _lastError = _lastErrorDetails = _lastFailure = null;
    _failingSince = null;
    _setState(isConfigured ? SyncState.idle : SyncState.disabled);
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
    // After the run however it ended: a follow-up is never lost.
    return _queued ??= running.catchError((Object _) {}).then((_) {
      _queued = null;
      return syncNow();
    });
  }

  static String _files(int n) => n == 1 ? '1 file' : '$n files';

  /// The token was read from the secure store (after start) or changed:
  /// sync may have become possible, or impossible.
  void _tokenChanged() {
    if (_state == SyncState.syncing) return;
    if (!isConfigured) {
      _setState(SyncState.disabled);
    } else if (_state == SyncState.disabled) {
      _setState(SyncState.idle);
    }
  }

  void _setState(SyncState state) {
    if (_disposed) return;
    if (state == SyncState.disabled) _failingSince = null;
    if (state != SyncState.syncing) {
      _progress = null;
      _pullFrom = null;
      _announcedWrites = 0;
    }
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
    tokens.removeListener(_tokenChanged);
    _timer?.cancel();
    _api?.close();
    unawaited(_remoteChanges.close());
    unawaited(_notices.close());
    super.dispose();
  }
}
