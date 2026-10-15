import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../domain/recording.dart';

/// Fetches a recording's missing parts from the sync server, [parallel] at
/// a time, in the order playback needs them: from the part [want]ed last
/// onwards, then the ones before it. Playback waits for a part with
/// [ready] (see `PlaybackController`).
class PartDownloads {
  PartDownloads(
    this.parts, {
    required Set<int> missing,
    required this.fetch,
    this.parallel = 3,
    this.onChange,
  }) : _queue = [...missing]..sort(),
       _totalMs = math.max(1, missing.fold(0, (sum, i) => sum + parts[i].durationMs)) {
    for (var i = 0; i < parts.length; i++) {
      if (!missing.contains(i)) _results[i] = true;
    }
    _pump();
  }

  final List<RecordingPart> parts;

  /// Fetches a blob; false if it can't be had.
  final Future<bool> Function(String sha) fetch;
  final int parallel;

  /// Called whenever a part arrived (or failed).
  final VoidCallback? onChange;

  /// Parts to fetch, the next first.
  final List<int> _queue;

  /// Whether each part is here (true) or couldn't be had (false); parts
  /// not settled yet are missing.
  final Map<int, bool> _results = {};
  final Map<int, Completer<bool>> _waiters = {};
  int _active = 0;
  final int _totalMs;
  int _doneMs = 0;
  bool _cancelled = false;

  /// Whether every part is here or settled.
  bool get complete => _queue.isEmpty && _active == 0;

  /// How much of the missing audio has arrived (0…1, by audio length).
  double get progress => math.min(1, _doneMs / _totalMs);

  /// Whether part [index] is here (true), couldn't be had (false), or is
  /// still coming (null).
  bool? resultOf(int index) => _results[index];

  /// Completes with whether part [index] is here, once it is settled
  /// (fetching it next if it isn't under way). With [retry], a part that
  /// couldn't be had is asked for again.
  Future<bool> ready(int index, {bool retry = false}) {
    if (retry && _results[index] == false) {
      _results.remove(index);
      _doneMs -= parts[index].durationMs;
      _queue.add(index);
    }
    final result = _results[index];
    if (result != null) return Future.value(result);
    want(index);
    return (_waiters[index] ??= Completer<bool>()).future;
  }

  /// Fetches part [index] and those after it before the others.
  void want(int index) {
    int rank(int i) => i >= index ? i - index : i + parts.length;
    _queue.sort((a, b) => rank(a).compareTo(rank(b)));
    _pump();
  }

  void _pump() {
    while (!_cancelled && _active < parallel && _queue.isNotEmpty) {
      _active++;
      unawaited(_fetch(_queue.removeAt(0)));
    }
  }

  Future<void> _fetch(int index) async {
    bool ok;
    try {
      ok = await fetch(parts[index].blob);
    } on Object catch (e) {
      debugPrint('Recording part failed to download: $e');
      ok = false;
    }
    _active--;
    if (_cancelled) return;
    _results[index] = ok;
    _doneMs += parts[index].durationMs;
    _waiters.remove(index)?.complete(ok);
    onChange?.call();
    _pump();
  }

  /// Stops fetching (the recording was closed); waiters hear false.
  void cancel() {
    _cancelled = true;
    for (final waiter in _waiters.values) {
      waiter.complete(false);
    }
    _waiters.clear();
  }
}
