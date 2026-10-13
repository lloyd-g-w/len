import 'package:flutter/material.dart';

/// A scroller whose cut-off ends fade out, so content that runs past the
/// edge (the phone's text format bar, a tall popover) shows there is more
/// to scroll to. An end fades only while content lies beyond it.
class ScrollFade extends StatefulWidget {
  const ScrollFade({
    super.key,
    required this.child,
    this.extent = 24,
    this.axis = Axis.horizontal,
    this.padding,
  });

  final Widget child;

  /// Length of each fade.
  final double extent;

  /// The scroll direction (a one-line row by default).
  final Axis axis;

  /// Padding inside the scroller.
  final EdgeInsetsGeometry? padding;

  @override
  State<ScrollFade> createState() => _ScrollFadeState();
}

class _ScrollFadeState extends State<ScrollFade> {
  final ScrollController _controller = ScrollController();

  /// Keeps the content's state when the fade comes and goes (it moves
  /// under the mask and back).
  final GlobalKey _scroller = GlobalKey();
  bool _start = false;
  bool _end = false;

  void _update(ScrollMetrics m) {
    final start = m.extentBefore > 0.5;
    final end = m.extentAfter > 0.5;
    if (start == _start && end == _end) return;
    setState(() {
      _start = start;
      _end = end;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scroller = NotificationListener<ScrollMetricsNotification>(
      key: _scroller,
      onNotification: (n) {
        _update(n.metrics);
        return false;
      },
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (n) {
          _update(n.metrics);
          return false;
        },
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: widget.axis,
          padding: widget.padding,
          child: widget.child,
        ),
      ),
    );
    if (!_start && !_end) return scroller;
    return ShaderMask(
      key: const ValueKey('scroll-fade'),
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final vertical = widget.axis == Axis.vertical;
        final length = vertical ? bounds.height : bounds.width;
        final f = (widget.extent / length).clamp(0.0, 0.5);
        return LinearGradient(
          begin: vertical ? Alignment.topCenter : Alignment.centerLeft,
          end: vertical ? Alignment.bottomCenter : Alignment.centerRight,
          colors: [
            if (_start) Colors.transparent else Colors.black,
            Colors.black,
            Colors.black,
            if (_end) Colors.transparent else Colors.black,
          ],
          stops: [0, f, 1 - f, 1],
        ).createShader(bounds);
      },
      child: scroller,
    );
  }
}
