import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../../platform/scan_runner.dart';
import 'scan_job.dart';
import 'scan_photo.dart';
import 'scan_result.dart';

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

  /// Width over height of the flattened page as the outline suggests (its
  /// top and left sides, turned): its shape until a preview is in.
  double get aspect {
    final w = (quad.topRight - quad.topLeft).distance,
        h = (quad.bottomLeft - quad.topLeft).distance;
    final a = h <= 0 || w <= 0 ? 1.0 : w / h;
    return turns.isOdd ? 1 / a : a;
  }

  /// Bumped on every change that the preview must follow.
  int _version = 0;
}

/// The pages of a scan, the one being adjusted and the look for all of
/// them: the model behind the scan screen. Previews of the flattened
/// pages render in the background (on a worker isolate natively).
class ScanSession extends ChangeNotifier {
  /// A session starting with [filter]; [onFilterChanged] hears the user
  /// pick another (e.g. to remember it for the next scan).
  ScanSession({
    this.previewEdge = 320,
    this.displayEdge = 1600,
    this._filter = ScanFilter.colour,
    this.onFilterChanged,
  });

  /// The long side of the page previews, in pixels.
  final int previewEdge;

  /// The long side the current page's photo is decoded at for the corner
  /// editor (and its large result rendered at), in pixels.
  final int displayEdge;

  /// The current page's photo as shown in the corner editor (only that
  /// page's is kept: photos are big); null while it decodes.
  ui.Image? get display => _display?.photo == current?.photo ? _display?.image : null;
  ({ScanPhoto photo, ui.Image image})? _display;

  /// Whether the current page is shown flattened and cleaned up (its
  /// [result]) instead of its photo with the corners.
  bool get showsResult => _showsResult;
  bool _showsResult = false;

  /// The current page flattened and cleaned up at [displayEdge] while
  /// [showsResult] (perhaps still of its previous outline or look while
  /// the new one renders); null until rendered.
  ui.Image? get result => switch (current) {
    final page? when _showsResult => _result.imageOf(page.photo),
    _ => null,
  };
  late final _result = ScanResultRenderer(edge: displayEdge, onReady: _resultReady);

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
  ScanFilter _filter;

  /// Hears every new [filter].
  final ValueChanged<ScanFilter>? onFilterChanged;

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
    _renderResult();
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
    if (_pages.isEmpty) _showsResult = false;
    _renderResult();
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

  /// Switches between the current page's photo with its corners and its
  /// [result].
  void toggleResult() {
    if (current == null) return;
    _showsResult = !_showsResult;
    _showsResult ? _renderResult() : _result.clear();
    notifyListeners();
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
    onFilterChanged?.call(value);
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
    if (page == current) _renderResult();
    notifyListeners();
    unawaited(_render(page, version));
  }

  /// Renders the current page's [result] anew while it is shown.
  void _renderResult() {
    final page = current;
    if (!_showsResult || page == null) return;
    _result.render((photo: page.photo, quad: page.quad, turns: page.turns, filter: _filter));
  }

  void _resultReady() {
    if (!_disposed) notifyListeners();
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
      image = await rgbaToImage(await renderScanPreview(job));
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

  @override
  void dispose() {
    _disposed = true;
    _result.dispose();
    _display?.image.dispose();
    for (final page in _pages) {
      page.preview?.dispose();
    }
    super.dispose();
  }
}
