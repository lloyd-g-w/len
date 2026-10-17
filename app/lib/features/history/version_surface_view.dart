import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/versions/versions.dart';
import '../../domain/paper.dart';
import '../../ink/images/element_images.dart';
import '../../ink/render/content_painter.dart';
import '../../ui/app_theme.dart';
import '../editor/document/missing_pdf_painter.dart';
import '../editor/document/page_backgrounds.dart';
import '../editor/document/page_painting.dart';
import 'version_ink_images.dart';
import 'version_sheets.dart';

export 'version_sheets.dart';

part 'version_sheet_painter.dart';

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

  /// The page shown; null for a canvas, or the page a paged version
  /// changed first (its thumbnail).
  final VersionPage? page;
  final ElementImages images;

  @override
  State<VersionSurfaceView> createState() => VersionSurfaceViewState();
}

/// The state of a [VersionSurfaceView]; public so tests can tell when its
/// picture has loaded ([loaded]).
class VersionSurfaceViewState extends State<VersionSurfaceView> {
  VersionSheet? _sheet;
  bool _loading = true;
  StreamSubscription<String>? _images;

  /// Counts images loaded meanwhile (the picture repaints for them).
  var _imagesShown = 0;

  /// The ink of a large sheet's thumbnail, rendered ([VersionInkImages]),
  /// and what it was asked for.
  ui.Image? _ink;
  InkImageKey? _inkKey;
  var _inkPending = false;

  /// Whether the version's page is shown (not the blank sheet shown while
  /// it loads, nor the one marked as not on this device).
  bool get loaded => !_loading && _sheet != null && !_inkPending;

  @override
  void initState() {
    super.initState();
    _load();
    _images = widget.images.changes.listen((_) {
      if (mounted) setState(() => _imagesShown++);
    });
  }

  @override
  void didUpdateWidget(VersionSurfaceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
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

  /// The ink image a thumbnail of [sheet] [size] logical pixels large
  /// draws, or null when it paints its strokes (small content, a preview).
  InkImageKey? _inkFor(VersionSheet sheet, Size size, double dpr) {
    if (size.width > _SheetPainter.thumbnailWidth || size.isEmpty) return null;
    if (sheet.strokes.length < VersionInkImages.minStrokes) return null;
    return (
      strokes: sheet.strokes,
      frame: (sheet.origin ?? Offset.zero) & sheet.page.size,
      width: (size.width * dpr).ceil(),
      height: (size.height * dpr).ceil(),
    );
  }

  /// Asks for [key]'s image (at layout, as the thumbnail comes into view).
  void _askInk(InkImageKey? key) {
    if (key == _inkKey) return;
    _inkKey = key;
    _inkPending = key != null;
    if (key == null) return;
    unawaited(
      widget.sheets.inkImages.image(key, wanted: () => mounted && _inkKey == key).then((image) {
        if (!mounted || _inkKey != key) {
          image?.dispose();
          return;
        }
        setState(() {
          _ink?.dispose();
          _ink = image;
          _inkPending = false;
        });
      }),
    );
  }

  @override
  void dispose() {
    unawaited(_images?.cancel());
    _ink?.dispose();
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
        // The shadow outside the clip: paper keeps its edge on a light sheet.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.xs),
          boxShadow: Shadows.low(brightness),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.xs),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Painted once (a canvas's thousands of strokes too), not with
              // every frame of the list around it.
              LayoutBuilder(
                builder: (context, box) {
                  final dpr = MediaQuery.devicePixelRatioOf(context);
                  final key = sheet == null ? null : _inkFor(sheet, box.biggest, dpr);
                  _askInk(key);
                  return RepaintBoundary(
                    child: CustomPaint(
                      painter: _SheetPainter(
                        sheet,
                        widget.images,
                        page == null ? null : widget.version,
                        page,
                        widget.sheets.backgrounds,
                        dpr,
                        _imagesShown,
                        ink: key == null ? null : (image: _ink, key: key),
                      ),
                    ),
                  );
                },
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
      ),
    );
  }
}
