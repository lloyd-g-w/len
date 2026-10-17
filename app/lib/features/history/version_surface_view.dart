import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/versions/versions.dart';
import '../../domain/notebook_page.dart';
import '../../domain/paper.dart';
import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';
import '../../ink/images/element_images.dart';
import '../../ui/app_theme.dart';
import '../editor/document/page_painting.dart';

/// A surface of a version ready to paint: its page (for a canvas, the
/// frame around its content, content moved to start at the origin).
typedef VersionSheet = ({
  NotebookPage page,
  List<Stroke> strokes,
  List<SurfaceElement> elements,
  Offset? origin,
});

/// Loads and keeps what version surfaces hold, for the history's
/// thumbnails and previews (packs fetched when not on this device).
class VersionSheets {
  VersionSheets(this.versions);

  final Versions versions;
  final Map<String, Future<VersionSheet?>> _loaded = {};

  /// Page [page] of [version] (null: its canvas), or null when its content
  /// cannot be had (offline, not on the server).
  Future<VersionSheet?> of(NotebookVersion version, VersionPage? page) {
    final key = page == null
        ? 'canvas:${version.canvas?.packs.join()}'
        : '${page.id}:${page.content.packs.join()}:${page.fields}';
    return _loaded[key] ??= _load(version, page).catchError((Object _) => null);
  }

  Future<VersionSheet?> _load(NotebookVersion version, VersionPage? page) async {
    final content = versions.content;
    if (page != null) {
      await content.ensure([page.content]);
      final c = await content.load(page.content, page.id);
      return (
        page: VersionContent.pageOf(version, page),
        strokes: c.strokes,
        elements: c.elements,
        origin: null,
      );
    }
    final canvas = version.canvas ?? VersionSurface.empty;
    await content.ensure([canvas]);
    final c = await content.load(canvas, version.notebookId);
    final frame = _frame([
      for (final s in c.strokes) s.bounds,
      for (final e in c.elements) e.bounds,
    ]);
    final origin = frame.topLeft;
    final paper = Paper.fromData(
      PaperStyle.parse(version.notebook['paper'] as String),
      version.notebook['paperData'] as Map<String, Object?>,
    );
    return (
      page: NotebookPage(
        id: version.notebookId,
        notebookId: version.notebookId,
        sortKey: 0,
        width: frame.width,
        height: frame.height,
        paper: paper ?? Paper.blank,
        paperColor: PaperColor.parse(version.notebook['paperColor'] as String?),
      ),
      strokes: [
        for (final s in c.strokes)
          s.withPoints([
            for (final p in s.points) StrokePoint(p.x - origin.dx, p.y - origin.dy, p.pressure),
          ]),
      ],
      elements: [for (final e in c.elements) e.copyWith(rect: e.rect.shift(-origin))],
      origin: origin,
    );
  }

  /// Content bounds padded to a page-like shape, never smaller than a
  /// readable minimum.
  static Rect _frame(List<Rect> bounds) {
    if (bounds.isEmpty) return const Rect.fromLTWH(0, 0, 480, 640);
    final content = bounds.reduce((a, b) => a.expandToInclude(b));
    const aspect = 0.75;
    var w = math.max(content.width * 1.1, 480.0);
    var h = math.max(content.height * 1.1, 480 / aspect);
    if (w / h > aspect) {
      h = w / aspect;
    } else {
      w = h * aspect;
    }
    return Rect.fromCenter(center: content.center, width: w, height: h);
  }
}

/// A read-only picture of a version's page (or canvas): paper, ink and
/// elements, as a piece of paper resting on the desk.
class VersionSurfaceView extends StatefulWidget {
  const VersionSurfaceView({
    super.key,
    required this.sheets,
    required this.version,
    this.page,
    required this.images,
  });

  final VersionSheets sheets;
  final NotebookVersion version;

  /// The page shown; null for a canvas.
  final VersionPage? page;
  final ElementImages images;

  @override
  State<VersionSurfaceView> createState() => _VersionSurfaceViewState();
}

class _VersionSurfaceViewState extends State<VersionSurfaceView> {
  VersionSheet? _sheet;
  bool _loading = true;
  StreamSubscription<String>? _images;

  @override
  void initState() {
    super.initState();
    _load();
    _images = widget.images.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(VersionSurfaceView old) {
    super.didUpdateWidget(old);
    if (old.version.id != widget.version.id || old.page?.id != widget.page?.id) _load();
  }

  void _load() {
    _loading = true;
    final asked = (widget.version, widget.page);
    unawaited(
      widget.sheets.of(widget.version, widget.page).then((sheet) {
        if (!mounted || asked != (widget.version, widget.page)) return;
        setState(() {
          _sheet = sheet;
          _loading = false;
        });
      }),
    );
  }

  @override
  void dispose() {
    unawaited(_images?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final sheet = _sheet;
    final ratio = sheet != null
        ? sheet.page.width / sheet.page.height
        : page == null
        ? 0.75
        : VersionContent.pageOf(widget.version, page).size.aspectRatio;
    final brightness = Theme.of(context).brightness;
    return AspectRatio(
      aspectRatio: ratio,
      child: DecoratedBox(
        decoration: BoxDecoration(boxShadow: Shadows.low(brightness)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _SheetPainter(
                sheet,
                widget.images,
                page == null ? null : widget.version,
                page,
              ),
            ),
            if (!_loading && sheet == null)
              Center(
                child: Icon(
                  Symbols.cloud_off_sharp,
                  size: Glyphs.menu,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  semanticLabel: 'Not on this device',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SheetPainter extends CustomPainter {
  _SheetPainter(this.sheet, this.images, this.version, this.page);

  final VersionSheet? sheet;
  final ElementImages images;
  final NotebookVersion? version;
  final VersionPage? page;

  @override
  void paint(Canvas canvas, Size size) {
    final sheet = this.sheet;
    final version = this.version;
    final page =
        sheet?.page ??
        (version != null && this.page != null ? VersionContent.pageOf(version, this.page!) : null);
    if (page == null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = PaperColor.white.paper);
      return;
    }
    final scale = size.width / page.width;
    canvas
      ..save()
      ..scale(scale);
    paintWholePage(
      canvas,
      page,
      strokes: sheet?.strokes ?? const [],
      elements: sheet?.elements ?? const [],
      scale: scale,
      images: images,
      miniature: true,
      worldOrigin: sheet?.origin,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SheetPainter old) => true;
}
