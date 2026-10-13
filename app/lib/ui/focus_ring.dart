import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'app_theme.dart';

/// Draws an accent ring around the focused control while the keyboard
/// drives focus (Tab, arrows), so keyboard users always see where they
/// are: the theme's calm focus overlay alone matches the selected plate.
/// Touch and mouse never show it. Wraps the app (`MaterialApp.builder`);
/// it only paints, so no layout changes.
///
/// Skipped: text fields (their border shows focus), focus scopes, and
/// areas larger than half the window (a canvas or a whole pane).
class FocusRing extends StatefulWidget {
  const FocusRing({super.key, required this.child});

  final Widget child;

  /// The ring's layer (for tests).
  static const Key paintKey = ValueKey('focus-ring');

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> with SingleTickerProviderStateMixin {
  /// Repaints every frame for a moment after focus moves, so the ring
  /// follows a control into place (a popover scaling in, a list scrolling
  /// it into view).
  late final Ticker _ticker = createTicker(_onTick);
  final _repaint = ValueNotifier<int>(0);
  Duration? _until;

  FocusManager get _focus => FocusManager.instance;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
    _focus.addHighlightModeListener(_modeChanged);
  }

  @override
  void dispose() {
    _focus.removeListener(_changed);
    _focus.removeHighlightModeListener(_modeChanged);
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _modeChanged(FocusHighlightMode _) => _changed();

  void _changed() {
    _repaint.value++;
    _until = null;
    if (_focus.highlightMode == FocusHighlightMode.traditional && !_ticker.isActive) {
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final until = _until ??= elapsed + Motion.slow;
    _repaint.value++;
    if (elapsed >= until) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _repaint.value++;
        return false;
      },
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                key: FocusRing.paintKey,
                painter: _RingPainter(repaint: _repaint, color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.repaint, required this.color}) : super(repaint: repaint);

  final Listenable repaint;
  final Color color;

  /// Space between the control and the ring.
  static const double _gap = 2;
  static const double _width = 2;

  /// The rect to ring, or null when nothing should show.
  static Rect? target(Size window) {
    // Painting can run while the focused element is inactive (moved or
    // being removed, still `mounted`); its tree lookups then assert. There
    // is no public way to ask whether it is active, so skip the frame.
    try {
      return _target(window);
    } on FlutterError {
      return null;
    }
  }

  static Rect? _target(Size window) {
    final manager = FocusManager.instance;
    if (manager.highlightMode != FocusHighlightMode.traditional) return null;
    final node = manager.primaryFocus;
    final context = node?.context;
    if (node == null || node is FocusScopeNode || context == null || !context.mounted) {
      return null;
    }
    // A focused element being taken out of the tree is detached before it
    // is unmounted: check that first, an ancestor lookup there throws.
    final render = context.findRenderObject();
    if (render is! RenderBox || !render.attached || !render.hasSize) return null;
    if (context.findAncestorWidgetOfExactType<EditableText>() != null) return null;
    final rect = node.rect;
    if (rect.isEmpty || rect.width * rect.height > window.width * window.height / 2) return null;
    return rect;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = target(size);
    if (rect == null) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(_gap + _width / 2), const Radius.circular(Radii.sm)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _width
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color;
}
