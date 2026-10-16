import 'dart:async';

import '../../../sync/remote_changes.dart';
import '../document/page_models.dart';
import '../document/page_thumbnail_cache.dart';

/// Keeps thumbnails that stay open beside the page (the page sidebar)
/// live: a page edited here is recorded again once the pen has rested
/// [delay] (its ink written to storage first, which thumbnails read), a
/// page changed on another device straight away. Nothing happens while
/// the pen keeps writing, nor per frame.
class ThumbnailRefresh {
  ThumbnailRefresh({
    required this.cache,
    required this.models,
    Stream<RemoteChanges>? remote,
    this.delay = const Duration(milliseconds: 600),
  }) {
    _edits = models.contentChanges.listen(_edited);
    _remote = remote?.listen((changes) => changes.strokeSurfaces.forEach(cache.changed));
  }

  final ThumbnailCache cache;
  final PageModels models;

  /// How long after the last edit a page is recorded again.
  final Duration delay;

  late final StreamSubscription<String> _edits;
  StreamSubscription<RemoteChanges>? _remote;
  final Set<String> _waiting = {};
  Timer? _timer;

  void _edited(String pageId) {
    _waiting.add(pageId);
    _timer?.cancel();
    _timer = Timer(delay, _refresh);
  }

  void _refresh() {
    for (final pageId in _waiting) {
      models.peek(pageId)?.flush(); // Thumbnails read what is stored.
      cache.changed(pageId);
    }
    _waiting.clear();
  }

  void dispose() {
    _timer?.cancel();
    unawaited(_edits.cancel());
    unawaited(_remote?.cancel());
  }
}
