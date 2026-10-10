import 'dart:async';
import 'dart:ui';

/// Recognises a still, single-finger long press (or a right click) on the
/// canvas, used to open a context menu.
///
/// Only one finger may be down: a second finger, a stylus, or moving more
/// than [slop] abandons the press.
class LongPressDetector {
  LongPressDetector({
    required this.onLongPress,
    this.duration = const Duration(milliseconds: 500),
    this.slop = 10,
  });

  /// Called with the screen position of a recognised long press.
  final void Function(Offset screen) onLongPress;
  final Duration duration;

  /// Maximum travel, in logical pixels.
  final double slop;

  int? _pointer;
  Offset _start = Offset.zero;
  Timer? _timer;
  int _down = 0;

  /// A finger touched down. [eligible] is false when the finger does not
  /// navigate (e.g. it is drawing), so it cannot start a long press.
  void down(int pointer, Offset position, {bool eligible = true}) {
    _down++;
    if (_down > 1 || !eligible) {
      reset();
      return;
    }
    _pointer = pointer;
    _start = position;
    _timer = Timer(duration, _fire);
  }

  void move(int pointer, Offset position) {
    if (pointer == _pointer && (position - _start).distance > slop) reset();
  }

  void up(int pointer) {
    _down = _down > 0 ? _down - 1 : 0;
    if (pointer == _pointer) reset();
  }

  /// Abandons any pending press (e.g. a stylus touched down).
  void reset() {
    _timer?.cancel();
    _timer = null;
    _pointer = null;
  }

  void _fire() {
    _timer = null;
    if (_pointer == null) return;
    _pointer = null;
    onLongPress(_start);
  }

  void dispose() => reset();
}

/// Recognises a right click released in place (a drag pans instead).
class SecondaryClickDetector {
  SecondaryClickDetector({required this.onClick, this.slop = 6});

  final void Function(Offset screen) onClick;
  final double slop;

  int? _pointer;
  Offset _start = Offset.zero;

  void down(int pointer, Offset position) {
    _pointer = pointer;
    _start = position;
  }

  void move(int pointer, Offset position) {
    if (pointer == _pointer && (position - _start).distance > slop) _pointer = null;
  }

  void up(int pointer) {
    if (pointer != _pointer) return;
    _pointer = null;
    onClick(_start);
  }

  void cancel() => _pointer = null;
}
