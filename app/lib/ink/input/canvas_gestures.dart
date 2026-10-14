import 'package:flutter/gestures.dart';

import 'double_tap_detector.dart';
import 'long_press_detector.dart';
import 'multi_finger_tap.dart';
import 'two_finger_hold.dart';

/// Canvas-level gestures recognised alongside drawing and navigation:
/// multi-finger taps (undo / redo), a navigating finger's double tap
/// (zoom), a finger long press and a right click (context menu).
///
/// `InkInputController` feeds it every raw event it sees; recognition never
/// claims the pointer, so drawing, panning and palm rejection behave as if
/// it weren't there.
class CanvasGestures {
  CanvasGestures({this.onMultiFingerTap, this.onContextMenu, this.onDoubleTap}) {
    doubleTap = DoubleTapDetector(onDoubleTap: (at) => onDoubleTap?.call(at));
    _twoFingerHold = TwoFingerHoldDetector(onHold: () => onTwoFingerHold?.call());
    _longPress = LongPressDetector(onLongPress: _contextMenu);
    _rightClick = SecondaryClickDetector(onClick: _contextMenu);
  }

  /// A quick tap with this many fingers (2 or 3).
  void Function(int fingers)? onMultiFingerTap;

  /// A long press with a navigating finger, or a right click, at a screen
  /// position.
  void Function(Offset screen)? onContextMenu;

  /// A double tap with one navigating finger, at a screen position.
  void Function(Offset screen)? onDoubleTap;

  /// Two fingers held still together.
  void Function()? onTwoFingerHold;
  late final TwoFingerHoldDetector _twoFingerHold;

  final MultiFingerTapDetector taps = MultiFingerTapDetector();
  late final DoubleTapDetector doubleTap;
  late final LongPressDetector _longPress;
  late final SecondaryClickDetector _rightClick;

  void _contextMenu(Offset screen) => onContextMenu?.call(screen);

  /// Any pointer touched down. [navigates] tells whether a finger pans
  /// (palm rejection on) rather than draws.
  void down(PointerDownEvent e, {required bool navigates}) {
    switch (e.kind) {
      case PointerDeviceKind.touch:
        taps.down(e.pointer, e.localPosition, e.timeStamp);
        _twoFingerHold.down(e.pointer, e.localPosition);
        // A still palm next to a (hovering) pen must not open a menu, nor
        // (often landing as two contacts) be a two-finger hold.
        final penNear = taps.isStylusNear(e.timeStamp);
        if (penNear) _twoFingerHold.reset();
        final eligible = navigates && !penNear;
        _longPress.down(e.pointer, e.localPosition, eligible: eligible);
        doubleTap.down(e.pointer, e.localPosition, e.timeStamp, eligible: eligible);
      case PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus:
        taps.noteStylus(e.timeStamp, down: true);
        _longPress.reset();
        _twoFingerHold.reset();
        doubleTap.reset();
      case PointerDeviceKind.mouse:
        if (e.buttons & kSecondaryMouseButton != 0) _rightClick.down(e.pointer, e.localPosition);
      default:
        break;
    }
  }

  void move(PointerMoveEvent e) {
    taps.move(e.pointer, e.localPosition);
    _twoFingerHold.move(e.pointer, e.localPosition);
    doubleTap.move(e.pointer, e.localPosition);
    _longPress.move(e.pointer, e.localPosition);
    _rightClick.move(e.pointer, e.localPosition);
  }

  void up(PointerUpEvent e) {
    if (e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus) {
      taps.noteStylusUp(e.timeStamp);
      return;
    }
    _rightClick.up(e.pointer);
    if (e.kind == PointerDeviceKind.touch) _longPress.up(e.pointer);
    if (e.kind == PointerDeviceKind.touch) _twoFingerHold.up(e.pointer);
    if (e.kind == PointerDeviceKind.touch) doubleTap.up(e.pointer, e.localPosition, e.timeStamp);
    final fingers = taps.up(e.pointer, e.localPosition, e.timeStamp);
    if (fingers != null) onMultiFingerTap?.call(fingers);
  }

  void cancel(PointerCancelEvent e) {
    // Like a lift: a pen still taken for touching would block taps for good.
    if (e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus) {
      taps.noteStylusUp(e.timeStamp);
      return;
    }
    taps.cancel(e.pointer);
    if (e.kind == PointerDeviceKind.touch) _twoFingerHold.up(e.pointer);
    if (e.kind == PointerDeviceKind.touch) doubleTap.cancel(e.pointer);
    if (e.kind == PointerDeviceKind.touch) _longPress.up(e.pointer);
    _rightClick.cancel();
  }

  /// The navigating pointers started moving the view (a pan or a pinch):
  /// what they do is not a tap, double tap or long press.
  void navigated() {
    taps.spoil();
    doubleTap.reset();
    _longPress.reset();
    _twoFingerHold.reset();
  }

  /// A stylus hovers: the hand is near, so touches are likely the palm.
  void hover(PointerHoverEvent e) {
    if (e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus) {
      taps.noteStylus(e.timeStamp);
      _longPress.reset();
      _twoFingerHold.reset();
      doubleTap.reset();
    }
  }

  void dispose() {
    _longPress.dispose();
    _twoFingerHold.dispose();
  }
}
