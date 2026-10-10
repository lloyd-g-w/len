import 'package:flutter/material.dart';

import '../../domain/paper.dart';
import '../../ink/render/paper_painter.dart';

/// A miniature page showing a template, drawn with the same renderer as
/// real pages so the preview is exactly what the user gets.
class TemplatePreview extends StatelessWidget {
  const TemplatePreview({super.key, required this.template, this.width = 84});

  final PageTemplate template;

  /// Width of the miniature; the height follows the page's aspect ratio.
  final double width;

  @override
  Widget build(BuildContext context) {
    final size = template.size;
    return SizedBox(
      width: width,
      height: width * size.height / size.width,
      child: CustomPaint(painter: TemplatePreviewPainter(template)),
    );
  }
}

/// Paints [template] scaled to fill the canvas.
///
/// A miniature of a real page would turn every pattern into a grey wash,
/// so the preview shows a smaller sheet of the same shape: proportions and
/// sections stay true while lines stay distinguishable.
class TemplatePreviewPainter extends CustomPainter {
  const TemplatePreviewPainter(this.template);

  final PageTemplate template;

  /// Size of the previewed sheet relative to the real page.
  static const double _sheet = 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    final page = Offset.zero & (template.size * _sheet);
    final scale = size.width / page.width;
    canvas
      ..save()
      ..scale(scale)
      ..clipRect(page);
    PaperRenderer.paintSheet(canvas, page, template.color, scale: scale, shadow: false);
    PaperRenderer.paintPattern(
      canvas,
      template.style,
      template.color,
      page,
      page: page,
      scale: scale,
      always: true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(TemplatePreviewPainter old) => old.template != template;
}
