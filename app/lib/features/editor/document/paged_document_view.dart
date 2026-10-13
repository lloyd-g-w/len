import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../ink/input/ink_input_controller.dart';
import '../../../ink/input/live_ink.dart';
import '../../../ink/render/ink_painters.dart';
import '../../../ui/app_theme.dart';
import 'document_controller.dart';
import 'document_layout.dart';
import 'document_painters.dart';
import 'page_backgrounds.dart';
import 'page_painting.dart';
import 'page_swipe.dart';

/// Shows a paged notebook as a scrollable stack of pages (or one page at a
/// time) and routes input to the page under the pointer.
///
/// Rendering mirrors `InkSurface` — paper, committed ink and live ink in
/// three layers behind repaint boundaries — but across every visible page,
/// each drawn from its own surface and picture cache.
class PagedDocumentView extends StatefulWidget {
  const PagedDocumentView({
    super.key,
    required this.controller,
    required this.input,
    required this.live,
    this.backgrounds,
  });

  final DocumentController controller;
  final InkInputController input;
  final LiveInk live;
  final PageBackgrounds? backgrounds;

  @override
  State<PagedDocumentView> createState() => _PagedDocumentViewState();
}

class _PagedDocumentViewState extends State<PagedDocumentView> with SingleTickerProviderStateMixin {
  final Set<int> _pointers = {};

  /// Slides the new page in when turning pages in single-page flow.
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: Motion.medium,
    value: 1,
  );
  late int _shownPage = _doc.currentPage;
  double _turnDirection = 1;

  /// Repaints the paper once an image template of a page is decoded.
  final _paperImagesChanged = ValueNotifier(0);
  StreamSubscription<String>? _imageChanges;

  @override
  void initState() {
    super.initState();
    _doc.addListener(_onDocument);
    _imageChanges = _doc.surfaces.images?.changes.listen((blob) {
      if (_doc.pages.any((p) => p.paper.image == blob)) {
        _paperImagesChanged.value++;
      }
    });
  }

  @override
  void didUpdateWidget(PagedDocumentView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onDocument);
      widget.controller.addListener(_onDocument);
    }
  }

  @override
  void dispose() {
    _doc.removeListener(_onDocument);
    unawaited(_imageChanges?.cancel());
    _paperImagesChanged.dispose();
    _turn.dispose();
    super.dispose();
  }

  late final _paperImages = switch (_doc.surfaces.images) {
    final images? => paperImagesOf(images),
    null => null,
  };

  void _onDocument() {
    final page = _doc.currentPage;
    if (page == _shownPage) return;
    if (_doc.flow == PageFlow.single) {
      _turnDirection = page > _shownPage ? 1 : -1;
      _turn.forward(from: 0);
    }
    _shownPage = page;
  }

  /// Start of a possible page-turning swipe (single-page flow).
  ({Offset at, Duration time})? _swipeStart;

  DocumentController get _doc => widget.controller;

  void _onLayout(Size size) {
    if (size == _doc.viewport.size) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _doc.viewport.setSize(size);
    });
  }

  void _down(PointerDownEvent e) {
    _doc.scroller.stop(); // Touching the page catches a running scroll.
    // The first pointer of a gesture picks the page; a stylus always does
    // (it cancels whatever a resting palm started anyway).
    final stylus = e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;
    // A press on the active page's selection (which may reach beyond the
    // page) keeps that page.
    final held = widget.input.content?.holds(e.localPosition) ?? false;
    if ((_pointers.isEmpty || stylus) && !held) _doc.activateAt(e.localPosition);
    _pointers.add(e.pointer);
    widget.input.handleDown(e);
    _trackSwipeStart(e);
  }

  void _up(PointerUpEvent e) {
    // Only a finger still navigating swipes (not a palm, nor one a pen
    // landing stopped).
    final navigating = widget.input.navigates(e.pointer);
    widget.input.handleUp(e);
    _pointers.remove(e.pointer);
    if (navigating) _maybeSwipe(e);
    _swipeStart = null;
  }

  void _cancel(PointerCancelEvent e) {
    widget.input.handleCancel(e);
    _pointers.remove(e.pointer);
    _swipeStart = null;
  }

  void _trackSwipeStart(PointerDownEvent e) {
    // One finger that pans (palm rejection on) may turn pages.
    final swipeable =
        _doc.flow == PageFlow.single &&
        e.kind == PointerDeviceKind.touch &&
        _pointers.length == 1 &&
        widget.input.navigates(e.pointer);
    _swipeStart = swipeable ? (at: e.localPosition, time: e.timeStamp) : null;
  }

  void _maybeSwipe(PointerUpEvent e) {
    final start = _swipeStart;
    if (start == null || _pointers.isNotEmpty) return;
    // Zoomed in on the page, a swipe pans it instead.
    final fit = _doc.frameTarget(_doc.currentPage)?.scale;
    if (fit == null || _doc.viewport.scale > fit * DocumentController.singleZoomedIn) return;
    final size = _doc.viewport.size;
    final turn = PageSwipe.turn(e.localPosition - start.at, e.timeStamp - start.time, size.width);
    if (turn != 0) _doc.goToPage(_doc.currentPage + turn);
  }

  @override
  Widget build(BuildContext context) {
    final input = widget.input;
    final desk = Surfaces.canvasBackdrop(Theme.of(context).brightness);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _onLayout(constraints.biggest);
        return MouseRegion(
          cursor: SystemMouseCursors.precise,
          onExit: (_) => input.handleExit(),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: input.handleMove,
            onPointerUp: _up,
            onPointerCancel: _cancel,
            onPointerHover: input.handleHover,
            onPointerSignal: (e) {
              GestureBinding.instance.pointerSignalResolver.register(e, input.handleSignal);
            },
            onPointerPanZoomStart: input.handlePanZoomStart,
            onPointerPanZoomUpdate: input.handlePanZoomUpdate,
            onPointerPanZoomEnd: input.handlePanZoomEnd,
            child: AnimatedBuilder(
              animation: _turn,
              builder: (context, child) {
                final t = Motion.standard.transform(_turn.value);
                return Opacity(
                  opacity: 0.4 + 0.6 * t,
                  child: Transform.translate(
                    offset: Offset(_turnDirection * (1 - t) * 48, 0),
                    child: child,
                  ),
                );
              },
              child: ListenableBuilder(
                listenable: _doc,
                builder: (context, _) => Stack(
                  fit: StackFit.expand,
                  children: [
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: DocumentPaperPainter(
                          layout: _doc.layout,
                          pages: _doc.pages,
                          viewport: _doc.viewport,
                          desk: desk,
                          devicePixelRatio: dpr,
                          backgrounds: widget.backgrounds,
                          paperImages: _paperImages,
                          paperImagesChanged: _paperImagesChanged,
                        ),
                      ),
                    ),
                    // The live highlighter stroke goes under the
                    // committed ink, as it will once committed.
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: LiveInkPainter(
                          live: widget.live,
                          viewport: _doc.pageViewport,
                          clip: _doc.pageViewport.contentBounds,
                          belowInk: true,
                        ),
                      ),
                    ),
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: DocumentInkPainter(
                          layout: _doc.layout,
                          pages: _doc.pages,
                          surfaces: _doc.surfaces,
                          viewport: _doc.viewport,
                          devicePixelRatio: dpr,
                          self: {input.content?.selection, input.content?.text},
                        ),
                      ),
                    ),
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: LiveInkPainter(
                          live: widget.live,
                          viewport: _doc.pageViewport,
                          clip: _doc.pageViewport.contentBounds,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
