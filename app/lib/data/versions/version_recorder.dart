import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/clock.dart';

/// Makes automatic versions while notebooks are edited (docs/ARCHITECTURE.md,
/// "Version history"): [quiet] after editing pauses, at most every
/// [maxInterval] while it goes on, and at once on [flush] (an editor
/// closing, the app going to the background).
class VersionRecorder {
  VersionRecorder(
    this.record, {
    this.clock = const Clock(),
    this.quiet = const Duration(minutes: 2),
    this.maxInterval = const Duration(minutes: 10),
  });

  /// Makes a version of a notebook if it changed (`Versions.record`).
  final Future<Object?> Function(String notebookId) record;
  final Clock clock;
  final Duration quiet;
  final Duration maxInterval;

  /// Per notebook with edits not in a version yet: since when, and the
  /// timer making one once editing has been quiet.
  final Map<String, ({int since, Timer timer})> _pending = {};

  /// The version being made per notebook (one at a time).
  final Map<String, Future<void>> _running = {};

  bool _disposed = false;

  /// Whether edits make versions (the app turns it on).
  bool enabled = false;

  /// Whether notebook [id] has edits waiting for a version.
  bool isPending(String id) => _pending.containsKey(id);

  /// Notes an edit in notebook [id].
  void noteEdit(String id) {
    if (_disposed || !enabled) return;
    final now = clock.nowMs();
    final old = _pending.remove(id);
    old?.timer.cancel();
    final since = old?.since ?? now;
    if (now - since >= maxInterval.inMilliseconds) {
      unawaited(_record(id));
      return;
    }
    _pending[id] = (since: since, timer: Timer(quiet, () => unawaited(_record(id))));
  }

  /// Makes the versions waiting (of notebook [id] only, if given) now.
  Future<void> flush([String? id]) => Future.wait([
    for (final notebook in [..._pending.keys])
      if (id == null || notebook == id) _record(notebook),
  ]);

  Future<void> _record(String id) {
    _pending.remove(id)?.timer.cancel();
    final previous = _running[id] ?? Future<void>.value();
    final next = previous.then((_) async {
      if (_disposed) return;
      try {
        await record(id);
      } on Object catch (e, stack) {
        debugPrint('Could not make a version of $id: $e\n$stack');
      }
    });
    _running[id] = next;
    return next.whenComplete(() {
      if (identical(_running[id], next)) _running.remove(id);
    });
  }

  /// Stops making versions (what waits is dropped).
  void dispose() {
    _disposed = true;
    for (final p in _pending.values) {
      p.timer.cancel();
    }
    _pending.clear();
  }
}
