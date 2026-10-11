import 'package:flutter/material.dart';

import '../../../../domain/text/text_data.dart';
import '../../../../ink/elements/list_marker.dart';
import '../../../../ink/elements/text_layout.dart';

/// A list marker inside the text field of the box being edited: painted
/// exactly like the canvas paints it; checkboxes toggle on tap.
class ListMarkerView extends StatelessWidget {
  const ListMarkerView({super.key, required this.marker, this.onToggle});

  final ListMarker marker;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final paint = CustomPaint(size: marker.size, painter: _MarkerPainter(marker));
    if (marker.para.list != ListKind.check || onToggle == null) return paint;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey('list-marker-${marker.line}'),
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: paint,
      ),
    );
  }
}

class _MarkerPainter extends CustomPainter {
  _MarkerPainter(this.marker);

  final ListMarker marker;

  @override
  void paint(Canvas canvas, Size size) {
    marker.paint(
      canvas,
      Offset.zero & size,
      number: (label, column) => TextBoxLayout.paintNumber(canvas, marker, label, column),
    );
  }

  @override
  bool shouldRepaint(_MarkerPainter old) =>
      old.marker.para != marker.para ||
      old.marker.number != marker.number ||
      old.marker.fontSize != marker.fontSize ||
      old.marker.color != marker.color ||
      old.marker.font != marker.font;
}
