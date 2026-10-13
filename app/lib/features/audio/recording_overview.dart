import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/blob_store.dart';
import '../../domain/recording.dart';
import '../../domain/waveform.dart';

/// When ink (strokes, text boxes, images) was made during a recording, in
/// audio positions: drawn as density on the scrubber, with a marker at the
/// start of each burst of writing to jump to.
class InkActivity {
  InkActivity(List<int> positions) : positions = List.unmodifiable(positions..sort());

  /// Maps content creation [times] (epoch ms) onto [recording]'s audio,
  /// leaving out content made outside its kept (trimmed) range.
  factory InkActivity.of(Recording recording, Iterable<int> times) =>
      InkActivity([for (final t in times) ?recording.inkPositionOf(t)]);

  static final InkActivity none = InkActivity([]);

  /// A pause in writing at least this long starts a new burst (marker).
  static const int burstGapMs = 4000;

  /// Audio positions (ms) at which content was made, sorted.
  final List<int> positions;

  bool get isEmpty => positions.isEmpty;

  /// The start of each burst of writing (ms), sorted.
  late final List<int> markers = [
    for (var i = 0; i < positions.length; i++)
      if (i == 0 || positions[i] - positions[i - 1] >= burstGapMs) positions[i],
  ];

  /// How much was written in each of [count] equal slices of the audio
  /// [fromMs]…[toMs], relative to the busiest slice (0…1).
  List<double> density(int count, {int fromMs = 0, required int toMs}) {
    if (count <= 0) return const [];
    final counts = List.filled(count, 0);
    final total = toMs - fromMs <= 0 ? 1 : toMs - fromMs;
    for (final p in positions) {
      if (p < fromMs || p > toMs) continue;
      counts[((p - fromMs) * count ~/ total).clamp(0, count - 1)]++;
    }
    final most = counts.fold(0, (a, b) => a > b ? a : b);
    return [for (final c in counts) most == 0 ? 0.0 : c / most];
  }

  /// The first marker after [positionMs] (one at it, just jumped to,
  /// counts as passed), or null.
  int? nextMarker(int positionMs) {
    for (final m in markers) {
      if (m > positionMs + 250) return m;
    }
    return null;
  }

  /// The marker before [positionMs], skipping one only just passed (so
  /// pressing "previous" repeatedly walks back), or null.
  int? previousMarker(int positionMs, {int graceMs = 2500}) {
    int? found;
    for (final m in markers) {
      if (m >= positionMs - graceMs) break;
      found = m;
    }
    return found;
  }
}

/// What the scrubber shows for a recording: its [waveform] (null while
/// loading or when it has none) and its [ink].
@immutable
class RecordingOverview {
  const RecordingOverview({this.waveform, required this.ink});

  final Waveform? waveform;
  final InkActivity ink;
}

/// Loads (once) and caches [RecordingOverview]s: the waveform blob (fetched
/// from the server when missing) and the notebook's ink times.
class RecordingOverviews extends ChangeNotifier {
  RecordingOverviews({required this.blobs, required this.fetch, required this.contentTimes});

  final BlobStore blobs;
  final Future<bool> Function(String sha) fetch;

  /// Creation times (epoch ms) of the notebook's content between two times.
  final List<int> Function(int from, int to) contentTimes;

  final Map<String, InkActivity> _ink = {};
  final Map<String, Waveform?> _waveforms = {};
  bool _disposed = false;

  /// The overview of [recording]: its ink at once, the waveform once
  /// loaded (listeners are notified then).
  RecordingOverview of(Recording recording) {
    // Positions move when parts outside the trim are dropped: the duration
    // tells those versions apart.
    final key =
        '${recording.id}/${recording.durationMs}/${recording.trimStartMs}/${recording.trimEndMs}';
    final ink = _ink[key] ??= _inkOf(recording);
    final sha = recording.waveform;
    if (sha.isEmpty) return RecordingOverview(ink: ink);
    if (!_waveforms.containsKey(sha)) {
      _waveforms[sha] = null;
      unawaited(_loadWaveform(sha));
    }
    return RecordingOverview(waveform: _waveforms[sha], ink: ink);
  }

  InkActivity _inkOf(Recording recording) {
    final timeline = recording.timeline;
    return InkActivity.of(
      recording,
      contentTimes(timeline.segments.first.startedAt, timeline.segments.last.endedAt),
    );
  }

  /// Forgets the ink times (the notebook's content changed).
  void invalidateInk() {
    if (_ink.isEmpty) return;
    _ink.clear();
    notifyListeners();
  }

  Future<void> _loadWaveform(String sha) async {
    try {
      var bytes = await blobs.read(sha);
      if (bytes == null && await fetch(sha)) bytes = await blobs.read(sha);
      final waveform = bytes == null ? null : Waveform.decode(bytes);
      if (waveform == null || _disposed) return;
      _waveforms[sha] = waveform;
      notifyListeners();
    } on Object {
      // No waveform: the scrubber shows a flat line.
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
