import 'package:flutter/material.dart';

/// A one-line horizontal scroller whose cut-off ends fade out, so a row of
/// controls that runs past the edge (the phone's text format bar) shows
/// there is more to scroll to. An end fades only while content lies beyond
/// it.
class ScrollFade extends StatefulWidget {
  const ScrollFade({super.key, required this.child, this.extent = 24});

  final Widget child;

  /// Width of each fade.
  final double extent;

  @override
  State<ScrollFade> createState() => _ScrollFadeState();
}

class _ScrollFadeState extends State<ScrollFade> {
  final ScrollController _controller = ScrollController();
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
          scrollDirection: Axis.horizontal,
          child: widget.child,
        ),
      ),
    );
    if (!_start && !_end) return scroller;
    return ShaderMask(
      key: const ValueKey('scroll-fade'),
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final f = (widget.extent / bounds.width).clamp(0.0, 0.5);
        return LinearGradient(
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
