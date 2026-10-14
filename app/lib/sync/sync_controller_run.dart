part of 'sync_controller.dart';

/// One sync run and how its outcome is reported.
extension _SyncRun on SyncController {
  Future<void> _run() async {
    await tokens.retryIfDue();
    if (!isConfigured) {
      _setState(SyncState.disabled);
      return;
    }
    final generation = _configGeneration;
    bool cancelled() => _disposed || generation != _configGeneration;

    _setState(SyncState.syncing);
    SyncApi? api;
    try {
      api = apiFactory(settings.syncUrl, tokens.token);
      final changes = await engine.sync(api, isCancelled: cancelled);
      if (cancelled()) return;
      _refreshTooLarge();
      _lastSuccess = DateTime.now();
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
    }
  }

  void _fail(
    String message,
    bool cancelled, {
    SyncFailure kind = SyncFailure.server,
    String? details,
    int files = 0,
  }) {
    if (cancelled) return;
    _filesNotUploaded = files;
    _refreshTooLarge();
    _lastError = message;
    _lastErrorDetails = details;
    _lastFailure = kind;
    _failingSince ??= DateTime.now();
    _setState(SyncState.error);
  }
}
