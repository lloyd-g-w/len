import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show EdgeInsets;

import '../../../data/element_repository.dart';
import '../../../data/stroke_repository.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/paper.dart';
import '../../../domain/paper_pattern.dart';
import '../../../ink/images/element_images.dart';
import '../../../ink/input/ink_input_controller.dart';
import '../../../ink/render/outline_preparer.dart';
import '../../../ink/surface_model.dart';
import '../../../ink/viewport.dart';
import '../tabs/open_notebooks.dart';
import 'document_layout.dart';
import 'document_scroller.dart';
import 'document_surfaces.dart';
import 'page_fit.dart';
import 'page_models.dart';
import 'page_viewport.dart';

part 'document_controller_state.dart';
part 'document_controller_viewport.dart';

/// State of an open paged notebook: its pages, their layout in document
/// space, the viewport, which page is current (shown in the indicator) and
/// which one receives input (the active page).
class DocumentController extends _DocumentState with _DocumentViewport {
  DocumentController({
    required super.pages,
    required StrokeRepository strokes,
    ElementRepository? elements,
    ElementImages? images,
    OutlinePreparer? outlines,
    super.flow = PageFlow.continuous,
    int initialPage = 0,
    super.initialView,
    super.fit = PageFit.auto,
    PageModels? models,
  }) : assert(pages.isNotEmpty, 'A document needs at least one page'),
       super(
         current: initialPage.clamp(0, pages.length - 1),
         surfaces: DocumentSurfaces(
           strokes,
           elements: elements,
           images: images,
           outlines: outlines,
           models: models,
         ),
       ) {
    _active = _current;
    surfaces.active = pages[_current].id;
    _relayout();
    // The page viewport needs the first active page too (its bounds clip
    // the content layer and keep inserted images on the page).
    pageViewport.showPage(_layout.frameOf(_active) ?? _layout.frames.first);
    viewport.addListener(_onViewport);
  }

  /// Screen padding around a fitted page.
  static const double fitPadding = PageFit.padding;

  /// Room (screen pixels) below the last page for the "add page" button in
  /// continuous flow.
  static const double footerExtent = 112;

  /// Changes how pages are zoomed and shows the current page that way.
  void setFit(PageFit fit) {
    _fit = fit;
    scrollToPage(_current, animateSamePage: true);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Pages

  /// Replaces the page list (after adding, deleting, reordering or a sync),
  /// keeping [keepPageId] (default: the current page) in view.
  void setPages(List<NotebookPage> pages, {String? keepPageId}) {
    if (pages.isEmpty) return;
    final keep = keepPageId ?? _pages[_current].id;
    final activeId = _pages[_active].id;
    final oldFrame = _layout.frameOf(_current);
    final screenTop = oldFrame == null ? null : viewport.toScreen(oldFrame.topLeft).dy;
    final ids = {for (final p in pages) p.id};
    if (!ids.contains(activeId)) {
      // The active page is going away: drop what the tools hold on it
      // before its surface is released.
      input
        ?..cancelDraw()
        ..content?.selection.clear()
        ..content?.text.discard();
    } else if (_pages.any((p) => !ids.contains(p.id) && _holdsHidden(p.id))) {
      // A selection reaching onto a page that goes lets go of it first.
      input?.content?.selection.clear();
    }
    _pages = pages;
    surfaces.retain(ids);
    final index = pages.indexWhere((p) => p.id == keep);
    _current = index == -1 ? _current.clamp(0, pages.length - 1) : index;
    final active = pages.indexWhere((p) => p.id == activeId);
    _relayout();
    _activate(active == -1 ? _current : active);
    // Keep the kept page where it was on screen, so edits elsewhere in the
    // notebook do not make the view jump.
    final frame = _layout.frameOf(_current);
    if (screenTop != null && frame != null && _framed) {
      viewport.panBy(Offset(0, screenTop - viewport.toScreen(frame.topLeft).dy));
    }
    _refreshVisible();
    notifyListeners();
  }

  /// Whether some owner (a selection) hides items on page [pageId].
  bool _holdsHidden(String pageId) => surfaces.models.peek(pageId)?.hasHidden ?? false;

  void setFlow(PageFlow flow) {
    if (flow == _flow) return;
    _flow = flow;
    _relayout();
    _activate(_current);
    _frame(_current);
    _refreshVisible();
    notifyListeners();
  }

  /// Shows page [index]: scrolls to it, or turns to it in single-page flow.
  void goToPage(int index) {
    if (index < 0 || index >= _pages.length) return;
    beforeJump?.call();
    scroller.stop();
    _current = index;
    if (_flow == PageFlow.single) _relayout();
    _activate(index);
    _frame(index);
    _refreshVisible();
    _current = index; // Not whatever the probe found mid-page.
    notifyListeners();
  }

  /// Like [goToPage], but scrolls there smoothly in continuous flow (and
  /// with [animateSamePage], also re-fits the page shown in single flow).
  void scrollToPage(int index, {bool animateSamePage = false}) {
    if (index < 0 || index >= _pages.length) return;
    final smooth = _flow == PageFlow.continuous || (animateSamePage && index == _current);
    final target = smooth ? frameTarget(index) : null;
    if (target == null) {
      goToPage(index);
      return;
    }
    beforeJump?.call();
    // Show the destination in the indicator straight away.
    _current = index;
    notifyListeners();
    scroller.animateTo(
      target.scale,
      target.offset,
      onDone: () {
        settleOn(index);
        _fitted = (scale: viewport.scale, offset: viewport.offset, size: viewport.size);
      },
    );
  }

  /// Single-page flow, after a gesture let go: unless zoomed in on the
  /// page, glides back to the whole page (a drag that did not turn the
  /// page, a pinch that ended near or below the fit). Returns whether it
  /// does.
  bool settleSingle() {
    final target = frameTarget(_current);
    if (_flow != PageFlow.single || target == null) return false;
    if (viewport.scale > target.scale * singleZoomedIn) return false;
    scrollToPage(_current, animateSamePage: true);
    return true;
  }

  /// In single-page flow, a zoom this much larger than the page fit counts
  /// as zoomed in (free to pan; a swipe no longer turns the page).
  static const double singleZoomedIn = 1.08;

  /// The planner page a link at [screen] leads to (a day, week or month
  /// printed on a planner page), or null when there is no link there.
  Paper? plannerLinkAt(Offset screen) {
    final world = viewport.toWorld(screen);
    final index = _layout.pageAt(world);
    if (index == null) return null;
    final page = _pages[index];
    if (!page.paper.style.isPlanner) return null;
    final local = world - _layout.frameOf(index)!.topLeft;
    final pattern = PaperPattern.of(page.paper, page.bounds, page: page.bounds);
    for (final link in pattern.links) {
      if (link.rect.contains(local)) return link.target;
    }
    return null;
  }

  /// The index of the first page with template [paper], or -1.
  int indexOfPaper(Paper paper) => _pages.indexWhere((p) => p.paper.sameSheet(paper));

  /// Makes the page under [screen] (or nearest to it) the active page.
  void activateAt(Offset screen) {
    final world = viewport.toWorld(screen);
    final index = _layout.pageAt(world) ?? _layout.nearestPage(world);
    if (index == null || index == _active) return;
    _activate(index);
    notifyListeners();
  }

  @override
  void dispose() {
    viewport.removeListener(_onViewport);
    scroller.dispose();
    pageViewport.dispose();
    viewport.dispose();
    surfaces.dispose();
    super.dispose();
  }
}
