import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../ink/remote_pointers.dart';
import '../../../ink/render/laser_painter.dart';
import '../../../ink/viewport.dart';
import '../../../ui/app_theme.dart';
import 'room_presence.dart';

/// Shows the pointers of the other devices in the notebook ([RemotePointers]):
/// a hovering pen or mouse as a small dot, a laser as the laser shows, each
/// labelled with its device's plate as presence shows it. Its own layer
/// (a [RepaintBoundary] driven by the pointers, no rebuilds), ticking only
/// while a laser fades; nothing at all while nobody points.
class RemotePointersOverlay extends StatefulWidget {
  const RemotePointersOverlay({
    super.key,
    required this.pointers,
    required this.viewport,
    required this.frameOf,
  });

  final RemotePointers pointers;
  final ViewportController viewport;

  /// Where surface [id] lies in [viewport]'s world (a page's frame; the
  /// canvas: [Rect.largest]), or null when this view does not show it.
  final Rect? Function(String id) frameOf;

  @override
  State<RemotePointersOverlay> createState() => _RemotePointersOverlayState();
}

class _RemotePointersOverlayState extends State<RemotePointersOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => _tick());

  @override
  void initState() {
    super.initState();
    widget.pointers.addListener(_onPointers);
  }

  @override
  void didUpdateWidget(RemotePointersOverlay old) {
    super.didUpdateWidget(old);
    if (old.pointers != widget.pointers) {
      old.pointers.removeListener(_onPointers);
      widget.pointers.addListener(_onPointers);
    }
  }

  @override
  void dispose() {
    widget.pointers.removeListener(_onPointers);
    _ticker.dispose();
    super.dispose();
  }

  void _onPointers() {
    if (widget.pointers.animating && !_ticker.isActive) _ticker.start();
  }

  void _tick() {
    final now = SchedulerBinding.instance.currentFrameTimeStamp.inMicroseconds / 1000;
    widget.pointers.tick(now);
    if (!widget.pointers.animating) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: RemotePointersPainter(
            pointers: widget.pointers,
            viewport: widget.viewport,
            frameOf: widget.frameOf,
            plate: Color.alphaBlend(Surfaces.selected(scheme), Surfaces.chrome(scheme)),
            label: Theme.of(context).textTheme.labelSmall!.copyWith(color: scheme.onSurface),
            dot: scheme.onSurface,
            halo: scheme.surface,
          ),
        ),
      ),
    );
  }
}

/// Paints [RemotePointers] over a view (see [RemotePointersOverlay]).
class RemotePointersPainter extends CustomPainter {
  RemotePointersPainter({
    required this.pointers,
    required this.viewport,
    required this.frameOf,
    required this.plate,
    required this.label,
    required this.dot,
    required this.halo,
  }) : super(repaint: Listenable.merge([pointers, viewport]));

  final RemotePointers pointers;
  final ViewportController viewport;
  final Rect? Function(String id) frameOf;

  /// The device plate's fill and text, the hover dot and its halo.
  final Color plate;
  final TextStyle label;
  final Color dot;
  final Color halo;

  /// The hovering pointer's dot (screen radius) and how far the plate sits
  /// from where it points.
  static const double dotRadius = 3.5;
  static const Offset plateOffset = Offset(Gaps.sm, Gaps.sm);

  /// Each laser's paint (its trail's strokes are kept between frames).
  final Expando<LaserPaint> _lasers = Expando();
  final Map<String, TextPainter> _initials = {};

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pointers.pointers) {
      final frame = frameOf(p.surface);
      if (frame == null) continue;
      final origin = frame == Rect.largest ? Offset.zero : frame.topLeft;
      final screenOrigin = viewport.toScreen(origin);
      Offset toScreen(Offset world) => world * viewport.scale + screenOrigin;
      Offset? tip;
      if (p.hover case final hover?) {
        tip = toScreen(hover);
        canvas
          ..drawCircle(tip, dotRadius + 1.5, Paint()..color = halo)
          ..drawCircle(tip, dotRadius, Paint()..color = dot);
      }
      if (p.laser.isVisible) {
        (_lasers[p.laser] ??= LaserPaint()).paint(
          canvas,
          p.laser,
          scale: viewport.scale,
          origin: screenOrigin,
        );
        final head = p.laser.head;
        if (head != null && p.laser.headAlpha > 0) {
          tip = toScreen(head) + Offset.fromDirection(0.8, LaserPainter.dotRadius(p.laser.config));
        }
      }
      if (tip != null) _plate(canvas, tip + plateOffset, pointers.nameOf(p.connection));
    }
  }

  /// The device's plate (its initial) with its top left at [at].
  void _plate(Canvas canvas, Offset at, String? name) {
    final text = RoomPresence.initialOf(name ?? 'Another device');
    final painter = _initials[text] ??= TextPainter(
      text: TextSpan(text: text, style: label),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    const edge = RoomPresence.plate;
    canvas.drawRRect(
      RRect.fromRectAndRadius(at & const Size.square(edge), const Radius.circular(Radii.xs)),
      Paint()..color = plate,
    );
    painter.paint(canvas, at + Offset((edge - painter.width) / 2, (edge - painter.height) / 2));
  }

  @override
  bool shouldRepaint(RemotePointersPainter old) =>
      old.pointers != pointers ||
      old.viewport != viewport ||
      old.frameOf != frameOf ||
      old.plate != plate ||
      old.label != label ||
      old.dot != dot ||
      old.halo != halo;
}
