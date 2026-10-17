part of 'sync_controller.dart';

/// One sync run and how its outcome is reported.
extension _SyncRun on SyncController {
  Future<void> _run() async {
    await _liveIdle();
    if (_disposed) return;
    await tokens.retryIfDue();
    if (_disposed) return;
    if (!isConfigured) {
      _setState(SyncState.disabled);
      return;
    }
    final generation = _configGeneration;
    bool cancelled() => _disposed || generation != _configGeneration;

    _setState(SyncState.syncing);
    _runStarts();
    SyncApi? api;
    try {
      api = _api = apiFactory(settings.syncUrl, tokens.token);
      final changes = await engine.sync(api, isCancelled: cancelled);
      if (cancelled()) return;
      _refreshTooLarge();
      _lastSuccess = clock.nowDate();
      settings.syncLastSuccess = _lastSuccess!.millisecondsSinceEpoch;
      final failed = engine.failedBlobUploads;
      if (failed == 0) {
        _lastError = _lastErrorDetails = _lastFailure = null;
        _failingSince = null;
        _setState(SyncState.idle);
      } else {
        // Everything else synced; the files are retried next time.
        _fail(
          '${SyncController._files(failed)} could not be uploaded and will be retried',
          false,
          details: engine.blobUploadError,
          files: failed,
        );
      }
      if (!changes.isEmpty) _remoteChanges.add(changes);
      if (engine.takeResync() case final notice?) _notices.add(notice);
      if (engine.takeLostFiles() case final notice?) _notices.add(notice);
      revivalNotices(changes, _titleOf).forEach(_notices.add);
    } on SyncException catch (e) {
      _fail(e.message, cancelled(), kind: e.kind, details: e.details);
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
      if (identical(_api, api)) _api = null;
    }
  }

  /// The title of notebook [id], unless it is gone.
  String? _titleOf(String id) => engine.repositories.notebooks.get(id)?.title;

  void _fail(
    String message,
    bool cancelled, {
    SyncFailure kind = SyncFailure.server,
    String? details,
    int files = 0,
  }) {
    if (cancelled) return;
    _filesNotUploaded = files;
    try {
      _refreshTooLarge();
    } catch (e) {
      // (The database may be what failed.) The error is reported anyway.
      debugPrint('Sync: cannot read the files too large to upload: $e');
    }
    _lastError = message;
    _lastErrorDetails = details;
    _lastFailure = kind;
    _failingSince ??= clock.nowDate();
    _setState(SyncState.error);
  }
}
