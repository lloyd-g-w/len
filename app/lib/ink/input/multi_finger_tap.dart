import 'dart:math' as math;
import 'dart:ui';

/// Recognises a quick tap with two or more fingers (two-finger tap = undo,
/// three-finger tap = redo) from raw touch events, telling it apart from
/// pinches and pans: every finger must lift within [maxDuration] of the
/// first touching down and none may travel further than [slop].
///
/// Palm safety: a gesture is ignored while a stylus is in contact or was
/// seen (touching or hovering) within [stylusQuiet] — a palm resting next
/// to the pen often lands as two or three "fingers".
class MultiFingerTapDetector {
  MultiFingerTapDetector({
    this.maxDuration = const Duration(milliseconds: 300),
    this.slop = 24,
    this.stylusQuiet = const Duration(milliseconds: 600),
    this.maxFingers = 3,
  });

  final Duration maxDuration;

  /// Maximum travel of any finger, in logical pixels.
  final double slop;
  final Duration stylusQuiet;

  /// More fingers than this is not a tap we handle (e.g. a whole hand).
  final int maxFingers;

  final Map<int, Offset> _starts = {};
  Duration _firstDown = Duration.zero;
  int _fingers = 0;
  bool _spoiled = false;
  Duration? _lastStylus;
  bool _stylusDown = false;

  /// A stylus touched down (or hovered, [down] false) at [time].
  void noteStylus(Duration time, {bool down = false}) {
    _lastStylus = time;
    _stylusDown = down;
    _spoiled = _spoiled || _starts.isNotEmpty;
  }

  /// The stylus lifted at [time].
  void noteStylusUp(Duration time) {
    _lastStylus = time;
    _stylusDown = false;
  }

  /// Whether a stylus is touching, or was seen within [stylusQuiet] of [time].
  bool isStylusNear(Duration time) {
    final last = _lastStylus;
    return _stylusDown || (last != null && time - last < stylusQuiet);
  }

  void down(int pointer, Offset position, Duration time) {
    if (_starts.isEmpty) {
      _firstDown = time;
      _fingers = 0;
      _spoiled = isStylusNear(time);
    }
    _starts[pointer] = position;
    _fingers = math.max(_fingers, _starts.length);
    if (_fingers > maxFingers) _spoiled = true;
  }

  void move(int pointer, Offset position) {
    final start = _starts[pointer];
    if (start != null && (position - start).distance > slop) _spoiled = true;
  }

  /// A finger lifted. Returns the number of fingers of a completed tap
  /// (≥ 2) when this was the last one up, otherwise null.
  int? up(int pointer, Offset position, Duration time) {
    if (!_starts.containsKey(pointer)) return null;
    move(pointer, position);
    _starts.remove(pointer);
    if (time - _firstDown > maxDuration) _spoiled = true;
    if (_starts.isNotEmpty) return null;
    final fingers = _fingers;
    _fingers = 0;
    if (_spoiled || fingers < 2) return null;
    return fingers;
  }

  /// A finger's gesture was cancelled by the platform.
  void cancel(int pointer) {
    if (_starts.remove(pointer) != null) _spoiled = true;
  }
}
