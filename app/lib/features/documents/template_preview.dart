import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../domain/image_data.dart';
import '../../domain/paper.dart';
import '../../ink/images/element_images.dart';
import '../../ink/render/paper_painter.dart';

/// A miniature page showing a template, drawn with the same renderer as
/// real pages so the preview is exactly what the user gets. Image
/// templates appear once decoded (from the app's shared image cache).
class TemplatePreview extends StatefulWidget {
  const TemplatePreview({super.key, required this.template, this.width = 84});

  final PageTemplate template;

  /// Width of the miniature; the height follows the page's aspect ratio.
  final double width;

  @override
  State<TemplatePreview> createState() => _TemplatePreviewState();
}

class _TemplatePreviewState extends State<TemplatePreview> {
  ElementImages? _images;
  StreamSubscription<String>? _changes;

  String? get _blob => widget.template.paper.image;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final images = AppScope.maybeRead(context)?.images;
    if (images == _images) return;
    _images = images;
    unawaited(_changes?.cancel());
    _changes = images?.changes.listen((blob) {
      if (blob == _blob && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  ui.Image? _lookup(String blob, double pixelWidth) =>
      _images?.imageFor(ImageData(blob: blob, width: 0, height: 0), pixelWidth);

  @override
  Widget build(BuildContext context) {
    final size = widget.template.size;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return SizedBox(
      width: widget.width,
      height: widget.width * size.height / size.width,
      child: CustomPaint(
        painter: TemplatePreviewPainter(
          widget.template,
          images: _blob == null ? null : (blob, _) => _lookup(blob, widget.width * dpr),
        ),
      ),
    );
  }
}

/// Paints [template] scaled to fill the canvas.
///
/// A miniature of a real page would turn every pattern into a grey wash,
/// so the preview shows a smaller sheet of the same shape: proportions and
/// sections stay true while lines stay distinguishable.
class TemplatePreviewPainter extends CustomPainter {
  const TemplatePreviewPainter(this.template, {this.images});

  final PageTemplate template;

  /// Decoded image templates.
  final PaperImageLookup? images;

  /// Size of the previewed sheet relative to the real page: half for
  /// repeating patterns, the real size for page layouts (their text and
  /// sections are laid out for it).
  static double sheetFor(PaperStyle style) => style.canvas || style.isRuled ? 0.5 : 1;

  @override
  void paint(Canvas canvas, Size size) {
    final page = Offset.zero & (template.size * sheetFor(template.style));
    final scale = size.width / page.width;
    canvas
      ..save()
      ..scale(scale)
      ..clipRect(page);
    PaperRenderer.paintSheet(canvas, page, template.color, scale: scale, shadow: false);
    PaperRenderer.paintPattern(
      canvas,
      template.paper,
      template.color,
      page,
      page: page,
      scale: scale,
      always: true,
      images: images,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(TemplatePreviewPainter old) =>
      old.template != template || (images != null) != (old.images != null) || images != null;
}
