import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../../platform/scan_runner.dart';
import 'scan_job.dart';
import 'scan_photo.dart';

export 'scan_job.dart' show Quad, ScanFilter;
export 'scan_photo.dart';

/// One page of a scan being set up: the photo, the outline to flatten
/// and how far to turn the result.
class ScanPageDraft {
  ScanPageDraft(this.photo) : quad = photo.initialQuad;

  final ScanPhoto photo;

  /// The document's corners in photo pixels.
  Quad quad;

  /// Quarter turns clockwise of the flattened page (0..3).
  int turns = 0;

  /// The flattened page, small (for the page strip); null until rendered.
  ui.Image? preview;

  /// Bumped on every change that the preview must follow.
  int _version = 0;
}

/// The pages of a scan, the one being adjusted and the look for all of
/// them: the model behind the scan screen. Previews of the flattened
/// pages render in the background (on a worker isolate natively).
class ScanSession extends ChangeNotifier {
  ScanSession({this.previewEdge = 320, this.displayEdge = 1600});

  /// The long side of the page previews, in pixels.
  final int previewEdge;

  /// The long side the current page's photo is decoded at for the corner
  /// editor, in pixels.
  final int displayEdge;

  /// The current page's photo as shown in the corner editor (only that
  /// page's is kept: photos are big); null while it decodes.
  ui.Image? get display => _display?.photo == current?.photo ? _display?.image : null;
  ({ScanPhoto photo, ui.Image image})? _display;

  final List<ScanPageDraft> _pages = [];

  /// The pages, in order.
  List<ScanPageDraft> get pages => List.unmodifiable(_pages);

  /// The page being adjusted (-1 without pages).
  int get index => _index;
  int _index = -1;

  /// The page being adjusted, if any.
  ScanPageDraft? get current => _index < 0 ? null : _pages[_index];

  /// How the pages are cleaned up.
  ScanFilter get filter => _filter;
  ScanFilter _filter = ScanFilter.colour;

  bool _disposed = false;

  /// Adds [photo] as a new page after the others and makes it the
  /// current one.
  void add(ScanPhoto photo) {
    _pages.add(ScanPageDraft(photo));
    _index = _pages.length - 1;
    _refresh(_pages.last);
    _showCurrent();
  }

  /// Replaces the current page's photo with [photo] (a retake), keeping
  /// its turns.
  void replaceCurrent(ScanPhoto photo) {
    final old = current;
    if (old == null) return;
    final page = ScanPageDraft(photo)..turns = old.turns;
    old.preview?.dispose();
    old._version++;
    _pages[_index] = page;
    _refresh(page);
    _showCurrent();
  }

  /// Makes page [i] the current one.
  void select(int i) {
    if (i == _index || i < 0 || i >= _pages.length) return;
    _index = i;
    notifyListeners();
    _showCurrent();
  }

  /// Removes the current page.
  void removeCurrent() {
    final page = current;
    if (page == null) return;
    _pages.removeAt(_index);
    page.preview?.dispose();
    page._version++; // A preview on its way is dropped.
    if (_index >= _pages.length) _index = _pages.length - 1;
    notifyListeners();
    _showCurrent();
  }

  /// Moves the current page's outline to [quad] (while a corner is dragged:
  /// [preview] false renders the preview only once the drag ends).
  void setQuad(Quad quad, {bool preview = true}) {
    final page = current;
    if (page == null) return;
    page.quad = quad;
    if (preview) {
      _refresh(page);
    } else {
      notifyListeners();
    }
  }

  /// Re-renders the current page's preview (after a drag).
  void updatePreview() {
    if (current case final page?) _refresh(page);
  }

  /// Whether the current page's outline is the whole photo.
  bool get isWholePhoto => current?.quad == current?.photo.bounds;

  /// Switches the current page between the whole photo and the document
  /// found in it (or, if none was found, back to the whole photo).
  void toggleWholePhoto() {
    final page = current;
    if (page == null) return;
    final bounds = page.photo.bounds;
    setQuad(page.quad == bounds ? page.photo.detected ?? bounds : bounds);
  }

  /// Turns the current page a quarter clockwise.
  void rotate() {
    final page = current;
    if (page == null) return;
    page.turns = (page.turns + 1) % 4;
    _refresh(page);
  }

  /// Sets the look of all pages.
  set filter(ScanFilter value) {
    if (value == _filter) return;
    _filter = value;
    for (final page in _pages) {
      _refresh(page);
    }
    if (_pages.isEmpty) notifyListeners();
  }

  /// Decodes the current page's photo for the corner editor (dropping the
  /// one shown before).
  void _showCurrent() {
    final photo = current?.photo;
    if (_display?.photo == photo) return;
    _display?.image.dispose();
    _display = null;
    if (photo != null) unawaited(_decode(photo));
  }

  Future<void> _decode(ScanPhoto photo) async {
    final ui.Image image;
    try {
      image = await photo.decode(displayEdge);
    } on Object catch (e) {
      debugPrint('Scan photo decode failed: $e');
      return;
    }
    if (_disposed || current?.photo != photo || _display != null) {
      image.dispose();
      return;
    }
    _display = (photo: photo, image: image);
    notifyListeners();
  }

  /// Renders [page]'s preview anew (the latest request wins).
  void _refresh(ScanPageDraft page) {
    final version = ++page._version;
    notifyListeners();
    unawaited(_render(page, version));
  }

  Future<void> _render(ScanPageDraft page, int version) async {
    final job = page.photo.previewJob(
      page.quad,
      quarterTurns: page.turns,
      filter: _filter,
      maxEdge: previewEdge,
    );
    final ui.Image image;
    try {
      image = await _toImage(await renderScanPreview(job));
    } on Object catch (e) {
      debugPrint('Scan preview failed: $e');
      return;
    }
    if (_disposed || version != page._version) {
      image.dispose();
      return;
    }
    page.preview?.dispose();
    page.preview = image;
    notifyListeners();
  }

  static Future<ui.Image> _toImage(RgbaImage page) {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      page.pixels,
      page.width,
      page.height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  @override
  void dispose() {
    _disposed = true;
    _display?.image.dispose();
    for (final page in _pages) {
      page.preview?.dispose();
    }
    super.dispose();
  }
}
