import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
///
/// Kept light, as the history builds a screen of them when it jumps: what
/// loads later (the sheet, its ink image, element images) repaints the
/// picture ([_SheetPicture]) instead of rebuilding it, and the ink image a
/// thumbnail needs is asked for when it is first painted, at its size.
class VersionSurfaceViewState extends State<VersionSurfaceView> {
  final _picture = _SheetPicture();
  bool _loading = true;
  StreamSubscription<String>? _images;

  /// The ink of a large sheet's thumbnail ([VersionInkImages]): what it was
  /// asked for, and whether it is still on its way.
  InkImageKey? _inkKey;
  var _inkPending = false;

  /// Whether the version's page is shown (not the blank sheet shown while
  /// it loads, nor the one marked as not on this device).
  bool get loaded => !_loading && _picture.sheet != null && _picture.painted && !_inkPending;

  /// Whether its ink is drawn from a rendered image ([VersionInkImages]).
  @visibleForTesting
  bool get showsInkImage => _picture.ink != null;

  @override
  void initState() {
    super.initState();
    _load();
    _images = widget.images.changes.listen((_) => _picture.imagesChanged());
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
        _loading = false;
        _picture.show(sheet);
        // Rebuilt only for the mark of a missing sheet (the picture
        // relays itself out and repaints).
        if (sheet == null) setState(() {});
      }),
    );
  }

  /// The shape shown until the sheet comes.
  double get _expectedRatio {
    final page = widget.page;
    return page == null ? 0.75 : VersionContent.pageOf(widget.version, page).size.aspectRatio;
  }

  /// The ink image a thumbnail of [sheet] [size] logical pixels large
  /// draws, or null when it paints its strokes (small content, a preview).
  static InkImageKey? _inkFor(VersionSheet sheet, Size size, double dpr) {
    if (size.width > _SheetPainter.thumbnailWidth || size.isEmpty) return null;
    if (sheet.strokes.length < VersionInkImages.minStrokes) return null;
    return (
      strokes: sheet.strokes,
      frame: (sheet.origin ?? Offset.zero) & sheet.page.size,
      width: (size.width * dpr).ceil(),
      height: (size.height * dpr).ceil(),
    );
  }

  /// The ink image to draw [sheet] with at [size] (asked for when it
  /// changes; null while it renders), or null when it paints its strokes.
  ({ui.Image? image, InkImageKey key})? _inkAt(VersionSheet sheet, Size size, double dpr) {
    final key = _inkFor(sheet, size, dpr);
    if (key != _inkKey) _askInk(key);
    return key == null ? null : (image: _picture.ink, key: key);
  }

  /// Asks for [key]'s image (when the thumbnail is painted at a new size).
  void _askInk(InkImageKey? key) {
    _inkKey = key;
    _inkPending = key != null;
    if (key == null) return;
    unawaited(
      widget.sheets.inkImages.image(key, wanted: () => mounted && _inkKey == key).then((image) {
        if (!mounted || _inkKey != key) {
          image?.dispose();
          return;
        }
        _inkPending = false;
        _picture.showInk(image);
      }),
    );
  }

  @override
  void dispose() {
    unawaited(_images?.cancel());
    _picture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    _picture.expectedRatio = _expectedRatio;
    final paper = _SheetBox(
      _SheetPainter(
        _picture,
        this,
        widget.images,
        page == null ? null : widget.version,
        page,
        widget.sheets.backgrounds,
        MediaQuery.devicePixelRatioOf(context),
        Theme.of(context).brightness,
      ),
    );
    if (_loading || _picture.sheet != null) return paper;
    return Stack(
      alignment: Alignment.center,
      children: [
        paper,
        Icon(
          Symbols.cloud_off_sharp,
          size: Glyphs.menu,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          semanticLabel: 'Not on this device',
        ),
      ],
    );
  }
}

/// What a [VersionSurfaceView] shows that arrives after it is built: its
/// sheet, the ink image of a large one's thumbnail, element images. Its
/// painter repaints when it changes.
class _SheetPicture extends ChangeNotifier {
  VersionSheet? sheet;
  ui.Image? ink;

  /// The width / height shown until the sheet comes.
  double expectedRatio = 0.75;

  /// The width / height of the picture.
  double get ratio {
    final page = sheet?.page;
    return page == null ? expectedRatio : page.width / page.height;
  }

  /// Whether the sheet has been painted since it came.
  var painted = false;

  void show(VersionSheet? sheet) {
    this.sheet = sheet;
    painted = false;
    notifyListeners();
  }

  void showInk(ui.Image? image) {
    ink?.dispose();
    ink = image;
    notifyListeners();
  }

  void imagesChanged() => notifyListeners();

  @override
  void dispose() {
    ink?.dispose();
    ink = null;
    super.dispose();
  }
}
