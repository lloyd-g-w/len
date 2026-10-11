import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/stickers/sticker.dart';
import '../../ink/images/element_images.dart';
import '../../ink/render/content_painter.dart';

/// A sticker's content drawn to fit its box (with the app's own
/// renderers, so it looks exactly as it will on the page). Images are
/// redrawn once decoded.
class StickerPreview extends StatefulWidget {
  const StickerPreview(this.content, {super.key, this.images, this.padding = 8});

  final StickerContent content;
  final ElementImages? images;
  final double padding;

  @override
  State<StickerPreview> createState() => _StickerPreviewState();
}

class _StickerPreviewState extends State<StickerPreview> {
  StreamSubscription<String>? _decoded;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    if (widget.content.elements.isNotEmpty) {
      _decoded = widget.images?.changes.listen((_) {
        if (mounted) setState(() => _generation++);
      });
    }
  }

  @override
  void dispose() {
    unawaited(_decoded?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _PreviewPainter(
      widget.content,
      widget.images,
      widget.padding,
      MediaQuery.devicePixelRatioOf(context),
      _generation,
    ),
    size: Size.infinite,
  );
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.content, this.images, this.padding, this.ratio, this.generation);

  final StickerContent content;
  final ElementImages? images;
  final double padding;
  final double ratio;
  final int generation;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = content.bounds;
    if (bounds.isEmpty || size.isEmpty) return;
    final area = (Offset.zero & size).deflate(padding);
    final scale = [
      area.width / bounds.width,
      area.height / bounds.height,
      2.0,
    ].reduce((a, b) => a < b ? a : b);
    canvas
      ..save()
      ..translate(
        area.center.dx - bounds.center.dx * scale,
        area.center.dy - bounds.center.dy * scale,
      )
      ..scale(scale);
    ContentPainter.paint(
      canvas,
      content.strokes,
      content.elements,
      images: images,
      pixelScale: scale * ratio,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      old.content != content ||
      old.images != images ||
      old.ratio != ratio ||
      old.generation != generation;
}
