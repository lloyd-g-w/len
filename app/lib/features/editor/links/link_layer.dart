import 'package:flutter/material.dart';

import '../../../domain/link_target.dart';
import '../../../domain/surface_element.dart';
import '../../../ink/surface_model.dart';
import '../editor_session.dart';

/// Shows where the links of the visible pages (or the canvas) are: a faint
/// tint with a dotted underline, the way GoodNotes marks links. Painted
/// over the content, never in exports; ignores pointers.
class LinkLayer extends StatelessWidget {
  const LinkLayer({super.key, required this.session});

  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    final color = HSLColor.fromColor(Theme.of(context).colorScheme.primary)
        .withLightness(0.45)
        .toColor();
    final doc = session.doc;
    if (doc == null) {
      final model = session.canvas!;
      final viewport = session.canvasViewport!;
      return IgnorePointer(
        child: CustomPaint(
          painter: _LinkPainter(
            color: color,
            repaint: Listenable.merge([model, viewport]),
            surfaces: () => [(model: model, origin: Offset.zero, clip: viewport.visibleWorld)],
            toScreen: viewport.toScreen,
          ),
        ),
      );
    }
    // The set of visible page models changes as pages scroll in and out.
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: doc,
        builder: (context, _) => CustomPaint(
          painter: _LinkPainter(
            color: color,
            // The surfaces forward their models' changes.
            repaint: Listenable.merge([doc.viewport, doc.surfaces]),
            surfaces: () {
              final visible = doc.viewport.visibleWorld;
              return [
                for (final i in doc.layout.visiblePages(visible))
                  if (doc.surfaces.peek(doc.pages[i].id)?.model case final model?)
                    (
                      model: model,
                      origin: doc.layout.frameOf(i)!.topLeft,
                      clip: visible.shift(-doc.layout.frameOf(i)!.topLeft),
                    ),
              ];
            },
            toScreen: doc.viewport.toScreen,
          ),
        ),
      ),
    );
  }
}

typedef _Surface = ({SurfaceModel model, Offset origin, Rect clip});

class _LinkPainter extends CustomPainter {
  _LinkPainter({
    required this.color,
    required Listenable repaint,
    required this.surfaces,
    required this.toScreen,
  }) : super(repaint: repaint);

  final Color color;
  final List<_Surface> Function() surfaces;
  final Offset Function(Offset world) toScreen;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color.withValues(alpha: 0.08);
    final line = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (final s in surfaces()) {
      for (final e in s.model.elementsNear(s.clip)) {
        if (!LinkElements.isLink(e) || s.model.isHidden(e.id)) continue;
        _paintLink(canvas, e, s.origin, fill, line);
      }
    }
  }

  void _paintLink(Canvas canvas, SurfaceElement e, Offset origin, Paint fill, Paint line) {
    final corners = [for (final c in e.corners) toScreen(c + origin)];
    canvas.drawPath(Path()..addPolygon(corners, true), fill);
    // A dotted underline along the bottom edge (bottom-left → bottom-right).
    final from = corners[3], to = corners[2];
    final length = (to - from).distance;
    if (length < 1) return;
    final step = (to - from) / length;
    for (var d = 0.0; d <= length; d += 5) {
      canvas.drawCircle(from + step * d, 0.9, line);
    }
  }

  @override
  bool shouldRepaint(_LinkPainter old) => old.color != color;
}
