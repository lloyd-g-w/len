part of 'editor_session.dart';

/// The zoom window of an [EditorSession]: opening it, its host and input,
/// and what the notebook keeps of it.
mixin _EditorSessionZoom {
  AppServices get services;
  SharedNotebook get shared;
  ToolSettings get tools;
  LiveInk get live;
  LiveInkRelay get relay;
  DocumentController? get doc;
  DocumentCommands? get commands;
  ViewportAnimator? get docAnimator;
  SurfaceModel? get canvas;
  ViewportController? get canvasViewport;
  CanvasNavigation? get canvasNav;
  Notebook get notebook;
  EdgeInsets get _chromeInsets;

  /// The zoom window: writing small through a magnified box.
  late final ZoomWindow zoomWindow = () {
    _zoomCreated = true;
    return ZoomWindow(
      host: _zoomHost(),
      input: _zoomInput,
      writesRightToLeft: () => services.preferences.zoomWritesRightToLeft,
    );
  }();
  bool _zoomCreated = false;

  /// Opens the zoom window (with the pen, unless the highlighter or the
  /// eraser is in hand: the box writes and erases), or closes it.
  void toggleZoomWindow() {
    final zoom = zoomWindow;
    if (!zoom.isOpen) {
      tools.reading = false; // The box writes.
      _toolForZoom();
    }
    zoom.toggle();
  }

  void _toolForZoom() {
    final tool = tools.tool;
    if (tool != EditorTool.highlighter && tool != EditorTool.eraser) tools.tool = EditorTool.pen;
  }

  /// The zoom window as the notebook left it (open where it was).
  void _restoreZoom(ZoomWindowState state) {
    if (state.open) _toolForZoom();
    zoomWindow.restore(state);
  }

  /// What the notebook keeps of the zoom window; null if it was never used.
  ZoomWindowState? get zoomState {
    if (!_zoomCreated) return null;
    final parked = _parkedZoom;
    return parked != null && !zoomWindow.isOpen ? parked : zoomWindow.state;
  }

  /// Remembers the zoom window as this editor shows it for the next time
  /// the notebook opens in the first pane (closed if it was never used).
  void saveZoomState() {
    if (services.database.isClosed) return;
    final zoom = zoomState;
    final keep = zoom == null || zoom.isEmpty ? null : zoom.encode();
    services.settings.setZoomWindow(notebook.id, keep);
  }

  /// The zoom window put away while presenting ([parkZoomWindow]).
  ZoomWindowState? _parkedZoom;

  /// Closes the zoom window for a while (presenting: its box takes no
  /// laser and would cover the page); [unparkZoomWindow] opens it again
  /// where it was. Kept for the notebook as open meanwhile.
  void parkZoomWindow() {
    if (!_zoomCreated || !zoomWindow.isOpen) return;
    _parkedZoom = zoomWindow.state;
    zoomWindow.close();
  }

  /// Opens the zoom window [parkZoomWindow] put away.
  void unparkZoomWindow() {
    final parked = _parkedZoom;
    _parkedZoom = null;
    if (parked != null && !zoomWindow.isOpen) zoomWindow.restore(parked);
  }

  ZoomHost _zoomHost() {
    final doc = this.doc;
    if (doc != null) {
      return DocumentZoomHost(
        doc: doc,
        animator: docAnimator!,
        chromeInsets: () => _chromeInsets,
        addPageAfter: commands!.addPageAfter,
      );
    }
    return CanvasZoomHost(
      surfaceId: shared.notebook.id,
      model: canvas!,
      main: canvasViewport!,
      animator: canvasNav!.animator,
      paper: () => shared.notebook.paper,
      chromeInsets: () => _chromeInsets,
    );
  }

  /// The zoom window's input: the editor's tools and live ink, seen through
  /// the box (its own palm rejection, no canvas gestures or pointer tools).
  InkInputController _zoomInput(SurfaceModel model, ZoomBoxViewport view) {
    final input = _zoomInk(model, view)
      // Highlights over PDF text snap to it there too.
      ..highlightSnap = doc == null ? null : PdfHighlightSnap(doc: doc!, info: shared.pdfInfo);
    relay.attach(input.events); // Other devices see it written there too.
    return input;
  }

  InkInputController _zoomInk(SurfaceModel model, ZoomBoxViewport view) => InkInputController(
    model: model,
    viewport: view,
    tools: tools,
    live: live,
    samples: openStylusSamples(
      wetInk: () => WetInkStyle.of(live, view.scale),
      wetInkNext: () => WetInkStyle.forNextStroke(tools, view.scale),
      // The page the frame is on now (it moves on to the next page).
      wetInkView: () => view.wetInkView(page: _zoomPage()),
    ),
    penButtonAction: () => services.preferences.penButtonAction,
    palms: services.palmGuard,
    stylusPointer: services.stylusPointer,
  );

  Rect? _zoomPage() {
    final frame = zoomWindow.frame;
    return frame == null ? null : zoomWindow.host.boundsOf(frame.surfaceId);
  }
}
