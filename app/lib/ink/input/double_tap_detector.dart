import 'dart:ui';

/// Recognises a single-finger double tap (double-tap zoom) from raw touch
/// events, without claiming the pointer: two quick, still taps close to
/// each other, with no other finger down at any time.
///
/// Only fingers that navigate count (with palm rejection off a finger
/// draws, and a tap is a dot). Palm safety is the caller's: it passes
/// `eligible: false` while a stylus is near, as for multi-finger taps.
class DoubleTapDetector {
  DoubleTapDetector({
    required this.onDoubleTap,
    this.maxTap = const Duration(milliseconds: 250),
    this.maxGap = const Duration(milliseconds: 300),
    this.slop = 18,
    this.maxDistance = 40,
  });

  /// Called with the screen position of the second tap.
  final void Function(Offset screen) onDoubleTap;

  /// Longest a tap may be held.
  final Duration maxTap;

  /// Longest pause between the first tap's lift and the second touch.
  final Duration maxGap;

  /// Maximum travel of a tap, in logical pixels.
  final double slop;

  /// Maximum distance between the two taps, in logical pixels.
  final double maxDistance;

  int _fingers = 0;
  int? _pointer;
  Offset _start = Offset.zero;
  Duration _downAt = Duration.zero;
  bool _spoiled = false;

  /// The first tap, while waiting for the second.
  ({Offset at, Duration upAt})? _first;

  /// A finger touched down; [eligible] is false when it may not start a
  /// double tap (it draws, or a stylus is near).
  void down(int pointer, Offset position, Duration time, {required bool eligible}) {
    _fingers++;
    if (_fingers > 1 || !eligible) {
      reset();
      return;
    }
    final first = _first;
    if (first != null &&
        (time - first.upAt > maxGap || (position - first.at).distance > maxDistance)) {
      _first = null;
    }
    _pointer = pointer;
    _start = position;
    _downAt = time;
    _spoiled = false;
  }

  void move(int pointer, Offset position) {
    if (pointer == _pointer && (position - _start).distance > slop) _spoiled = true;
  }

  /// A finger lifted at [time]. Fires [onDoubleTap] when this completes a
  /// double tap.
  void up(int pointer, Offset position, Duration time) {
    if (_fingers > 0) _fingers--;
    if (pointer != _pointer) return;
    _pointer = null;
    move(pointer, position);
    if (_spoiled || time - _downAt > maxTap) {
      _first = null;
      return;
    }
    final first = _first;
    if (first == null) {
      _first = (at: _start, upAt: time);
      return;
    }
    _first = null;
    onDoubleTap(_start);
  }

  /// A finger's gesture was cancelled by the platform.
  void cancel(int pointer) {
    if (_fingers > 0) _fingers--;
    if (pointer == _pointer) reset();
  }

  /// Forgets any tap in progress (e.g. a second finger or a stylus).
  void reset() {
    _pointer = null;
    _first = null;
    _spoiled = true;
  }
}
