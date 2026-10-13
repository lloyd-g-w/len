import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../../ink/render/laser_painter.dart';
import '../../../ink/tools/laser.dart';
import '../../../ink/viewport.dart';

/// Shows a [LaserTrail] over the surface. Self-contained so that the laser
/// costs only its own repaint: a [RepaintBoundary] around a [LaserPainter]
/// driven by the trail (no rebuilds), and a ticker that runs only while
/// something is visible to fade it.
class LaserOverlay extends StatefulWidget {
  const LaserOverlay({super.key, required this.trail, required this.viewport});

  final LaserTrail trail;
  final ViewportController viewport;

  @override
  State<LaserOverlay> createState() => _LaserOverlayState();
}

class _LaserOverlayState extends State<LaserOverlay> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => _tick());

  @override
  void initState() {
    super.initState();
    widget.trail.addListener(_onTrail);
  }

  @override
  void didUpdateWidget(LaserOverlay old) {
    super.didUpdateWidget(old);
    if (old.trail != widget.trail) {
      old.trail.removeListener(_onTrail);
      widget.trail.addListener(_onTrail);
    }
  }

  @override
  void dispose() {
    widget.trail.removeListener(_onTrail);
    _ticker.dispose();
    super.dispose();
  }

  // Frames only while something fades: a dot held under a still (pressed
  // or hovering) pointer repaints when it moves, not every frame.
  void _onTrail() {
    if (widget.trail.animating && !_ticker.isActive) _ticker.start();
  }

  void _tick() {
    // Frame time (monotonic; fake time in tests).
    final now = SchedulerBinding.instance.currentFrameTimeStamp.inMicroseconds / 1000;
    widget.trail.tick(now);
    if (!widget.trail.animating) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        painter: LaserPainter(trail: widget.trail, viewport: widget.viewport),
      ),
    ),
  );
}
