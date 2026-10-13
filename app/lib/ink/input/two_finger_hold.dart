import 'dart:async';
import 'dart:ui';

/// Recognises two fingers held still together for [duration] (a
/// two-finger long press), e.g. to hide focus mode's last controls.
///
/// Exactly two fingers: a third, a stylus, either finger moving more than
/// [slop] (a pinch or a pan) or lifting abandons it.
class TwoFingerHoldDetector {
  TwoFingerHoldDetector({
    required this.onHold,
    this.duration = const Duration(milliseconds: 600),
    this.slop = 12,
  });

  final VoidCallback onHold;
  final Duration duration;

  /// Maximum travel of either finger, in logical pixels.
  final double slop;

  final Map<int, Offset> _starts = {};
  Timer? _timer;
  bool _spoilt = false;

  void down(int pointer, Offset position) {
    _starts[pointer] = position;
    if (_starts.length == 2 && !_spoilt) {
      _timer = Timer(duration, _fire);
    } else {
      _cancel(spoil: _starts.length > 2);
    }
  }

  void move(int pointer, Offset position) {
    final start = _starts[pointer];
    if (start != null && (position - start).distance > slop) _cancel(spoil: true);
  }

  void up(int pointer) {
    _starts.remove(pointer);
    _cancel(spoil: _starts.isNotEmpty);
    if (_starts.isEmpty) _spoilt = false;
  }

  /// Abandons any pending hold (e.g. a stylus touched down).
  void reset() => _cancel(spoil: _starts.isNotEmpty);

  void _cancel({required bool spoil}) {
    _timer?.cancel();
    _timer = null;
    if (spoil) _spoilt = true;
  }

  void _fire() {
    _timer = null;
    _spoilt = true; // Once per touch.
    onHold();
  }

  void dispose() => _timer?.cancel();
}
