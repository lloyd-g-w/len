import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/app_database.dart';
import '../../data/blob_store.dart';
import '../../data/raster_store.dart';
import '../../data/storage_queries.dart';
import '../../platform/storage_survey.dart' as platform;
import '../../sync/sync_controller.dart';

/// How "Free up" went ([StorageOverview.freeUp]).
sealed class FreeUpOutcome {
  const FreeUpOutcome();
}

/// Copies of [count] files were removed, [bytes] in all.
final class FreedUp extends FreeUpOutcome {
  const FreedUp(this.bytes, this.count);

  final int bytes;
  final int count;
}

/// The server could not be asked which files it holds: nothing removed.
final class ServerUnreachable extends FreeUpOutcome {
  const ServerUnreachable();
}

/// Settings → Storage's figures (UX_AUDIT R16-7): what Len stores on this
/// device by kind, the notebooks taking the most, the files the sync
/// server holds whose copies here could go, and the cached rasters.
///
/// Lives in `AppServices`, so Settings shows the last figures at once
/// while [refresh] measures again (on a worker isolate natively).
class StorageOverview extends ChangeNotifier {
  StorageOverview({
    required this.database,
    required this.blobs,
    required this.sync,
    required this.rasters,
    required this.keep,
    this.measure = platform.surveyStorage,
  });

  final AppDatabase database;
  final BlobStore blobs;
  final SyncController sync;

  /// The level-of-detail raster cache, if the platform keeps one.
  final RasterStore? rasters;

  /// Notebooks whose files stay here (open in the editor: they may be
  /// needed offline).
  final Set<String> Function() keep;

  /// Measures the database (`platform/storage_survey`).
  final Future<StorageSurvey> Function(AppDatabase database, {Set<String> keep}) measure;

  /// The latest figures, null until first measured.
  StorageSurvey? get survey => _survey;
  StorageSurvey? _survey;

  /// Bytes of cached rasters (null: none kept on this platform).
  int? get previews => _previews;
  int? _previews;

  /// Whether a "Free up" is under way.
  bool get freeing => _freeing;
  bool _freeing = false;

  /// Cached previews take enough to offer clearing them.
  static const int significantPreviews = 1 << 20;

  /// Whether "Free up" may be offered: sync is on and some copies could go.
  bool get canFreeUp => sync.isConfigured && (_survey?.freeable ?? 0) > 0;

  Future<void>? _refreshing;
  bool _again = false;
  bool _disposed = false;

  /// Measures again; calls while one runs share it, with one more run after.
  Future<void> refresh() {
    if (_refreshing case final running?) {
      _again = true;
      return running;
    }
    return _refreshing = _refresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh() async {
    do {
      _again = false;
      if (database.isClosed) return;
      final StorageSurvey survey;
      try {
        survey = await measure(database, keep: keep());
      } on Object catch (e) {
        debugPrint('Cannot measure storage: $e');
        return;
      }
      final previews = await rasters?.size();
      if (_disposed) return;
      _survey = survey;
      _previews = previews;
      notifyListeners();
    } while (_again && !_disposed);
  }

  /// Removes this device's copies of files the sync server holds, as
  /// measured now, after asking the server that it still has each one;
  /// files of notebooks open in the editor, files not yet uploaded and
  /// those [StorageQueries.kept] says must stay are left.
  Future<FreeUpOutcome> freeUp() async {
    _freeing = true;
    notifyListeners();
    try {
      await refresh();
      final ids = _survey?.freeableIds ?? const [];
      if (ids.isEmpty) return const FreedUp(0, 0);
      final answer = await sync.blobsOnServer(ids);
      if (answer == null) return const ServerUnreachable();
      final kept = StorageQueries(database.db).kept(keep: keep());
      final removed = await blobs.removeLocalCopies(
        answer.held,
        stillRemovable: (sha) => answer.current() && !kept.contains(sha),
      );
      return FreedUp(removed.bytes, removed.count);
    } finally {
      _freeing = false;
      if (!_disposed) {
        notifyListeners();
        unawaited(refresh());
      }
    }
  }

  /// Deletes the cached rasters (they are drawn again when needed).
  Future<void> clearPreviews() async {
    await rasters?.clear();
    await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
