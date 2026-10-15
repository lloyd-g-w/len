import 'dart:collection';
import 'dart:ui' show FramePhase, FrameTiming, Offset;

import 'package:flutter/foundation.dart';

/// One moment the low-latency ink may have flickered (or something worth
/// knowing when it did), at [atUs] (monotonic clock, µs).
@immutable
class FlickerEntry {
  const FlickerEntry(this.atUs, this.kind, this.detail);

  final int atUs;

  /// `gap` (the overlay let go of ink before Flutter's frame with it could
  /// be on screen), `end` (the same for the committed stroke), `geometry`
  /// (the overlay's ink of a stroke reaches outside Flutter's committed
  /// ink), `retract` (a predicted tip drawn, then taken back), `samples`
  /// (Flutter saw fewer samples than the overlay drew), `unanswered` (the
  /// overlay dropped a contact Dart never answered), `cancel` (the overlay
  /// stopped drawing a stroke: why).
  final String kind;
  final String detail;

  @override
  String toString() => '${(atUs / 1000).toStringAsFixed(1)} ms  $kind  $detail';
}

/// A record of hand-over timing anomalies of the Android low-latency ink
/// (`WetInkOverlay.kt`), to capture one on the device when the pen
/// flickers (docs/INK_LAB.md, *Flicker log*). Off unless [enabled] (on in
/// debug builds; the Ink Lab switches it): nothing is measured otherwise.
///
/// The overlay tells when it let go of each Flutter frame's ink
/// ([frameReleased]); Flutter's frame timings ([frameTimings], batched by
/// the engine) tell when that frame finished rasterising. A frame is on
/// screen a display frame after that at the earliest, so a release before
/// then means the ink was on neither layer for a while: a flicker.
class FlickerLog extends ChangeNotifier {
  FlickerLog({bool enabled = kDebugMode}) {
    _enabled = enabled;
  }

  /// The app's log.
  static final FlickerLog instance = FlickerLog();

  /// Entries kept, newest last.
  static const int capacity = 500;

  bool _enabled = false;
  bool get enabled => _enabled;
  set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    _frames.clear();
    notifyListeners();
  }

  final ListQueue<FlickerEntry> _entries = ListQueue();

  /// What was logged, oldest first.
  List<FlickerEntry> get entries => List.unmodifiable(_entries);

  /// Strokes the overlay drew and let go of since [clear]; frames judged.
  int strokes = 0, frames = 0;

  /// The farthest a predicted tip was taken back (px), and how often by
  /// more than [retractLimitPx].
  double worstRetractPx = 0;
  int retracts = 0;

  /// The largest geometry difference seen (px).
  double worstGeometryPx = 0;

  /// A predicted tip taken back further than this is logged (px).
  static const double retractLimitPx = 0.5;

  /// Overlay ink reaching further than this outside Flutter's is logged.
  static const double geometryLimitPx = 0.5;

  /// Display frame interval (µs): a rasterised frame shows at the next
  /// refresh at the earliest.
  int frameUs = 8333;

  // Frames reported to the overlay, by Dart's frame id, until judged.
  final Map<int, _Frame> _frames = {};

  void _add(int atUs, String kind, String detail) {
    _entries.addLast(FlickerEntry(atUs, kind, detail));
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
    notifyListeners();
  }

  /// Dart reported frame [id] to the overlay at [sentUs].
  void frameReported(int id, int sentUs) {
    if (!_enabled) return;
    _frames[id] = _Frame(sentUs);
    if (_frames.length > 1024) _frames.remove(_frames.keys.first);
  }

  /// The frame Dart reported as [id] showed a committed stroke.
  void frameEnded(int id) => _frames[id]?.end = true;

  /// The overlay let go of frame [id]'s ink at [atUs]; [end]: of the
  /// committed stroke it shows (its contact went then).
  void frameReleased(int id, int atUs, {bool end = false}) {
    final f = _frames[id];
    if (f == null || f.end != end) return;
    f.releasedUs = atUs;
    _judge(id, f);
  }

  /// Flutter's frame timings: each reported frame was built in one of
  /// them (its report goes out right after the build).
  void frameTimings(List<FrameTiming> timings) {
    if (!_enabled || _frames.isEmpty) return;
    for (final MapEntry(key: id, value: f) in _frames.entries.toList()) {
      if (f.rasterUs != null) continue;
      FrameTiming? built;
      for (final t in timings) {
        final finish = t.timestampInMicroseconds(FramePhase.buildFinish);
        final start = t.timestampInMicroseconds(FramePhase.buildStart);
        if (start <= f.sentUs && finish <= f.sentUs + 1000) {
          if (built == null || finish > built.timestampInMicroseconds(FramePhase.buildFinish)) {
            built = t;
          }
        }
      }
      if (built == null ||
          f.sentUs - built.timestampInMicroseconds(FramePhase.buildFinish) > 50000) {
        continue;
      }
      f.rasterUs = built.timestampInMicroseconds(FramePhase.rasterFinish);
      _judge(id, f);
    }
  }

  void _judge(int id, _Frame f) {
    final released = f.releasedUs, raster = f.rasterUs;
    if (released == null || raster == null) return;
    _frames.remove(id);
    frames++;
    if (f.end) strokes++;
    final shownUs = raster + frameUs;
    if (released >= shownUs) return;
    final late = (shownUs - released) / 1000;
    final built = (raster - f.sentUs) / 1000;
    _add(
      released,
      f.end ? 'end' : 'gap',
      '${f.end ? 'committed stroke' : 'frame'} #$id: overlay let go '
      '${((released - f.sentUs) / 1000).toStringAsFixed(1)} ms after the report, '
      'Flutter rasterised it ${built.toStringAsFixed(1)} ms after: ink missing for '
      '≈ ${late.toStringAsFixed(1)} ms',
    );
  }

  /// The overlay took a predicted tip back by [px] at [atUs].
  void retract(double px, int atUs) {
    if (!_enabled) return;
    if (px > worstRetractPx) worstRetractPx = px;
    if (px <= retractLimitPx) return;
    retracts++;
    _add(atUs, 'retract', 'predicted tip taken back ${px.toStringAsFixed(2)} px');
  }

  /// The overlay's ink of a stroke reached [px] outside Flutter's
  /// committed ink (at [where], overlay px).
  void geometry(double px, Offset where, int atUs) {
    if (!_enabled) return;
    if (px > worstGeometryPx) worstGeometryPx = px;
    if (px <= geometryLimitPx) return;
    _add(
      atUs,
      'geometry',
      'overlay ink ${px.toStringAsFixed(2)} px outside the committed stroke at '
          '(${where.dx.toStringAsFixed(0)}, ${where.dy.toStringAsFixed(0)}) px',
    );
  }

  /// The overlay drew [overlay] samples of a stroke Flutter saw [flutter] of.
  void samples(int flutter, int overlay, int atUs) {
    if (!_enabled || flutter >= overlay) return;
    _add(atUs, 'samples', 'Flutter saw $flutter of the $overlay samples the overlay drew');
  }

  /// Something else worth knowing ([kind] as in [FlickerEntry.kind]).
  void note(String kind, String detail, int atUs) {
    if (_enabled) _add(atUs, kind, detail);
  }

  /// Forgets everything logged.
  void clear() {
    _entries.clear();
    _frames.clear();
    strokes = frames = retracts = 0;
    worstRetractPx = worstGeometryPx = 0;
    notifyListeners();
  }

  /// A one-line summary.
  String get summary =>
      '$strokes strokes, $frames frames judged, ${_entries.length} entries; worst retract '
      '${worstRetractPx.toStringAsFixed(2)} px, worst geometry '
      '${worstGeometryPx.toStringAsFixed(2)} px';

  /// The whole log as text, to share.
  String toText() => [summary, ..._entries.map((e) => e.toString())].join('\n');
}

class _Frame {
  _Frame(this.sentUs);
  final int sentUs;
  bool end = false;
  int? releasedUs, rasterUs;
}
