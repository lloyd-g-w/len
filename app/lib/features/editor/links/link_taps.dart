import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Follows links — link elements and planner links (a day on a month
/// calendar, a week number, …) — on taps that do not write: a finger tap
/// while fingers navigate (stylus mode), or a Ctrl/⌘-click. Watches
/// pointers without taking part in the gesture arena, so drawing, panning
/// and zooming are unaffected.
class LinkTaps extends StatefulWidget {
  const LinkTaps({
    super.key,
    required this.fingersNavigate,
    required this.follow,
    required this.child,
  });

  /// Whether one-finger touches pan rather than draw.
  final bool Function() fingersNavigate;

  /// Follows the link at a tapped screen point, if there is one.
  final void Function(Offset screen) follow;
  final Widget child;

  /// Longest press and farthest movement that still count as a tap.
  static const Duration maxTapDuration = Duration(milliseconds: 350);
  static const double maxTapSlop = 12;

  @override
  State<LinkTaps> createState() => _LinkTapsState();
}

class _LinkTapsState extends State<LinkTaps> {
  /// The single pointer that may become a link tap.
  ({int pointer, Offset at, Duration time})? _candidate;
  int _down = 0;

  bool _eligible(PointerDownEvent e) => switch (e.kind) {
    PointerDeviceKind.touch => widget.fingersNavigate(),
    PointerDeviceKind.mouse =>
      e.buttons == kPrimaryMouseButton &&
          (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed),
    _ => false,
  };

  void _onDown(PointerDownEvent e) {
    _down++;
    _candidate = _down == 1 && _eligible(e)
        ? (pointer: e.pointer, at: e.localPosition, time: e.timeStamp)
        : null;
  }

  void _onMove(PointerMoveEvent e) {
    final c = _candidate;
    if (c != null &&
        c.pointer == e.pointer &&
        (e.localPosition - c.at).distance > LinkTaps.maxTapSlop) {
      _candidate = null;
    }
  }

  void _onUp(PointerUpEvent e) {
    _down = _down > 0 ? _down - 1 : 0;
    final c = _candidate;
    _candidate = null;
    if (c == null || c.pointer != e.pointer) return;
    if (e.timeStamp - c.time > LinkTaps.maxTapDuration) return;
    widget.follow(c.at);
  }

  void _onCancel(PointerCancelEvent e) {
    _down = _down > 0 ? _down - 1 : 0;
    _candidate = null;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _onDown,
    onPointerMove: _onMove,
    onPointerUp: _onUp,
    onPointerCancel: _onCancel,
    child: widget.child,
  );
}
