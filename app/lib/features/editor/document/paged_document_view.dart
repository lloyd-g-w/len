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
import 'single_page_turns.dart';

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

class _PagedDocumentViewState extends State<PagedDocumentView> with TickerProviderStateMixin {
  final Set<int> _pointers = {};

  /// Slides the new page in when turning pages in single-page flow.
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: Motion.medium,
    value: 1,
  );
  late int _shownPage = _doc.currentPage;
  double _turnDirection = 1;

  /// How far the new page slides in from (a page turned by a swipe comes
  /// from further, carrying on the finger's motion).
  double _turnFrom = _slide;
  static const double _slide = 48;

  /// Glides a page that followed a finger back when the swipe didn't turn.
  late final AnimationController _settle = AnimationController(vsync: this, duration: Motion.medium)
    ..addListener(_settling);
  double _settleFrom = 0;

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
    _settle.dispose();
    _turns.dispose();
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
      final swiped = _turns.follow.value != 0;
      final width = _doc.viewport.size.width;
      _turnFrom = swiped ? (width / 3).clamp(_slide, 160).toDouble() : _slide;
      _stopFollowing();
      _turn.forward(from: 0);
    }
    _shownPage = page;
  }

  void _settling() =>
      _turns.follow.value = _settleFrom * (1 - Motion.standard.transform(_settle.value));

  /// The page that followed a finger glides back into place.
  void _settleBack() {
    _settleFrom = _turns.follow.value;
    if (_settleFrom == 0) return;
    Motion.reduced(context) ? _stopFollowing() : _settle.forward(from: 0);
  }

  void _stopFollowing() {
    _settle.stop();
    _turns.follow.value = 0;
  }

  /// Swipes, trackpad swipes and the wheel turn pages in single-page flow.
  late final SinglePageTurns _turns = SinglePageTurns(_doc);

  DocumentController get _doc => widget.controller;

  void _onLayout(Size size) {
    if (size == _doc.viewport.size) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _doc.viewport.setSize(size);
    });
  }

  void _down(PointerDownEvent e) {
    _doc.scroller.stop(); // Touching the page catches a running scroll.
    _stopFollowing(); // Input maps to the page where it really is.
    // The first pointer of a gesture picks the page; a stylus always does
    // (it cancels whatever a resting palm started anyway).
    final stylus = e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;
    // A press on the active page's selection (which may reach beyond the
    // page) keeps that page.
    final held = widget.input.content?.holds(e.localPosition) ?? false;
    if ((_pointers.isEmpty || stylus) && !held) _doc.activateAt(e.localPosition);
    _pointers.add(e.pointer);
    widget.input.handleDown(e);
    // One finger that pans (palm rejection on; not a palm) may swipe.
    final finger = e.kind == PointerDeviceKind.touch && widget.input.navigates(e.pointer);
    _turns.fingerDown(e, alone: finger && _pointers.length == 1);
  }

  void _up(PointerUpEvent e) {
    // Only the last finger, still navigating, swipes (not one a pen
    // landing stopped).
    final navigating = widget.input.navigates(e.pointer);
    widget.input.handleUp(e);
    _pointers.remove(e.pointer);
    if (navigating && _pointers.isEmpty) {
      if (_turns.fingerUp(e) == 0) _settleBack();
    } else {
      _turns.cancelSwipe();
      _settleBack();
    }
  }

  void _move(PointerMoveEvent e) {
    widget.input.handleMove(e);
    _turns.fingerMove(e);
  }

  void _cancel(PointerCancelEvent e) {
    widget.input.handleCancel(e);
    _pointers.remove(e.pointer);
    _turns.cancelSwipe();
    _settleBack();
  }

  void _signal(PointerSignalEvent e) {
    if (e is PointerScrollEvent && _turns.wheel(e)) return;
    widget.input.handleSignal(e);
  }

  @override
  Widget build(BuildContext context) {
    final input = widget.input;
    final brightness = Theme.of(context).brightness;
    final desk = Surfaces.canvasBackdrop(brightness);
    final shadows = Shadows.low(brightness);
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
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _cancel,
            onPointerHover: input.handleHover,
            onPointerSignal: (e) {
              GestureBinding.instance.pointerSignalResolver.register(e, _signal);
            },
            onPointerPanZoomStart: (e) {
              input.handlePanZoomStart(e);
              _turns.trackpadStart(e);
            },
            onPointerPanZoomUpdate: (e) {
              input.handlePanZoomUpdate(e);
              _turns.trackpadUpdate(e);
            },
            onPointerPanZoomEnd: (e) {
              input.handlePanZoomEnd(e);
              _turns.trackpadEnd(e);
            },
            child: AnimatedBuilder(
              animation: Listenable.merge([_turn, _turns.follow]),
              builder: (context, child) {
                final t = Motion.standard.transform(_turn.value);
                final dx = _turnDirection * (1 - t) * _turnFrom + _turns.follow.value;
                return Opacity(
                  opacity: 0.4 + 0.6 * t,
                  child: Transform.translate(offset: Offset(dx, 0), child: child),
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
                          shadows: shadows,
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
