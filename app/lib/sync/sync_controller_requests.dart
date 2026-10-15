part of 'sync_controller.dart';

/// [SyncController]'s requests outside sync runs: checking a configuration,
/// fetching a file when it is shown, asking which files the server holds.
mixin _SyncRequests {
  SyncEngine get engine;
  SettingsRepository get settings;
  SyncTokenStore get tokens;
  SyncApi Function(String url, String token) get apiFactory;
  bool get isConfigured;
  bool get _disposed;
  int get _configGeneration;
  StreamController<String> get _notices;

  /// Verifies a configuration without saving it and returns what the
  /// server says of itself. Throws [SyncException].
  Future<ServerInfo> test({required String url, required String token}) async {
    final api = apiFactory(SyncController._normalizeUrl(url), token.trim());
    try {
      return await api.check();
    } finally {
      api.close();
    }
  }

  /// Downloads blob [sha] from the server if it is not stored locally.
  /// Returns whether it is available now; never throws (a missing blob is
  /// retried the next time it is needed). A file Free up removed here that
  /// the server no longer has is named to the user, once per run of the app
  /// ([notices]).
  Future<bool> fetchBlob(String sha) async {
    final blobs = engine.blobs;
    if (blobs == null) return false;
    if (await blobs.has(sha)) return true;
    if (!isConfigured || _disposed) return false;
    // Switching servers (or one losing its history) resets the uploaded
    // marks; a download still under way must not mark it on the new one.
    final generation = _configGeneration;
    final serverId = settings.syncServerId;
    SyncApi? api;
    try {
      api = apiFactory(settings.syncUrl, tokens.token);
      final fetched = await BlobSync(blobs).download(
        api,
        sha,
        fromCurrentServer: () =>
            generation == _configGeneration && serverId == settings.syncServerId,
      );
      if (!fetched && !_disposed && !_toldMissing.contains(sha)) {
        if (FreedFiles(blobs, engine.blobReferences).missingNotice(sha) case final notice?) {
          _toldMissing.add(sha);
          _notices.add(notice);
        }
      }
      return fetched;
    } on SyncException catch (e) {
      debugPrint('Cannot fetch blob $sha: ${e.message}');
      return false;
    } finally {
      api?.close();
    }
  }

  /// Which of [shas] the sync server stores now, asked blob by blob, and
  /// a check whether that still holds for the server this device syncs
  /// with (no other server or server history since). Null when sync is
  /// off or the server can't be asked: then nothing counts as held.
  Future<({Set<String> held, bool Function() current})?> blobsOnServer(
    Iterable<String> shas,
  ) async {
    if (!isConfigured || _disposed) return null;
    final generation = _configGeneration;
    final serverId = settings.syncServerId;
    bool current() => generation == _configGeneration && serverId == settings.syncServerId;
    SyncApi? api;
    try {
      api = apiFactory(settings.syncUrl, tokens.token);
      final held = <String>{};
      for (final sha in shas) {
        if (!current()) return null;
        if (await api.hasBlob(sha)) held.add(sha);
      }
      return current() ? (held: held, current: current) : null;
    } on SyncException catch (e) {
      debugPrint('Cannot ask the server for blobs: ${e.message}');
      return null;
    } finally {
      api?.close();
    }
  }

  /// Freed files found missing on the server that the user was told of.
  final Set<String> _toldMissing = {};
}
