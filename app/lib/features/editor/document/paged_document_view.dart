import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../ink/input/ink_input_controller.dart';
import '../../../ink/input/live_ink.dart';
import '../../../ink/render/ink_painters.dart';
import 'document_controller.dart';
import 'document_layout.dart';
import 'document_painters.dart';
import 'page_backgrounds.dart';

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
    this.fingersNavigate,
  });

  final DocumentController controller;
  final InkInputController input;
  final LiveInk live;
  final PageBackgrounds? backgrounds;

  /// Whether one-finger touches pan rather than draw (palm rejection on);
  /// enables swiping between pages in single-page flow.
  final bool Function()? fingersNavigate;

  @override
  State<PagedDocumentView> createState() => _PagedDocumentViewState();
}

class _PagedDocumentViewState extends State<PagedDocumentView> {
  final Set<int> _pointers = {};

  /// Start of a possible page-turning swipe (single-page flow).
  Offset? _swipeStart;
  DateTime? _swipeTime;

  DocumentController get _doc => widget.controller;

  void _onLayout(Size size) {
    if (size == _doc.viewport.size) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _doc.viewport.setSize(size);
    });
  }

  void _down(PointerDownEvent e) {
    // The first pointer of a gesture picks the page; a stylus always does
    // (it cancels whatever a resting palm started anyway).
    final stylus = e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;
    // A press on the active page's selection (which may reach beyond the
    // page) keeps that page.
    final held = widget.input.content?.holds(e.localPosition) ?? false;
    if ((_pointers.isEmpty || stylus) && !held) _doc.activateAt(e.localPosition);
    _pointers.add(e.pointer);
    _trackSwipeStart(e);
    widget.input.handleDown(e);
  }

  void _up(PointerUpEvent e) {
    widget.input.handleUp(e);
    _pointers.remove(e.pointer);
    _maybeSwipe(e);
  }

  void _cancel(PointerCancelEvent e) {
    widget.input.handleCancel(e);
    _pointers.remove(e.pointer);
    _swipeStart = null;
  }

  void _trackSwipeStart(PointerDownEvent e) {
    final swipeable =
        _doc.flow == PageFlow.single &&
        e.kind == PointerDeviceKind.touch &&
        _pointers.length == 1 &&
        (widget.fingersNavigate?.call() ?? false);
    _swipeStart = swipeable ? e.localPosition : null;
    _swipeTime = DateTime.now();
  }

  void _maybeSwipe(PointerUpEvent e) {
    final start = _swipeStart;
    _swipeStart = null;
    if (start == null || _pointers.isNotEmpty) return;
    final delta = e.localPosition - start;
    final quick = DateTime.now().difference(_swipeTime!) < const Duration(milliseconds: 700);
    final pageFits = _doc.layout.bounds.width * _doc.viewport.scale <= _doc.viewport.size.width;
    if (!quick || !pageFits || delta.dx.abs() < 80 || delta.dx.abs() < 2 * delta.dy.abs()) {
      return;
    }
    _doc.goToPage(_doc.currentPage + (delta.dx < 0 ? 1 : -1));
  }

  @override
  Widget build(BuildContext context) {
    final input = widget.input;
    final desk = Theme.of(context).colorScheme.surfaceContainerHigh;
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
        );
      },
    );
  }
}
