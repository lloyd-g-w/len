import 'package:flutter/widgets.dart';

import '../../app_services.dart';
import '../../domain/notebook.dart';
import '../../domain/preferences.dart';
import '../../ink/input/canvas_gestures.dart';
import '../../ink/input/ink_input_controller.dart';
import '../../ink/input/live_ink.dart';
import '../../ink/input/wet_ink.dart';
import '../../ink/navigation/kinetic_pan.dart';
import '../../ink/navigation/viewport_animator.dart';
import '../../ink/surface_model.dart';
import '../../ink/tool_settings.dart';
import '../../ink/tools/content_tools.dart';
import '../../ink/viewport.dart';
import '../../platform/stylus_samples.dart';
import '../documents/pdf/pdf_background_cache.dart';
import 'canvas/canvas_navigation.dart';
import 'document/document_commands.dart';
import 'document/document_controller.dart';
import 'document/document_layout.dart';
import 'document/document_selection.dart';
import 'document/page_backgrounds.dart';
import 'document/page_fit.dart';
import 'document/undo_target.dart';
import 'double_tap_zoom.dart';
import 'images/editor_images.dart';
import 'links/editor_links.dart';
import 'pdf/pdf_highlight_snap.dart';
import 'pdf/pdf_interaction.dart';
import 'shared/shared_notebook.dart';
import 'tabs/open_notebooks.dart';
import 'zoom/zoom_box_viewport.dart';
import 'zoom/zoom_host.dart';
import 'zoom/zoom_hosts.dart';
import 'zoom/zoom_window.dart';

/// The engine side of one open editor: tool settings, input routing, the
/// content tools, undo, and either one infinite-canvas surface or a paged
/// document. Owns (and disposes) all of it; widgets only read it.
///
/// The surfaces' models, their undo history and the PDF caches belong to
/// the [shared] notebook (another view of the same notebook uses the same
/// ones); this session only holds them.
class EditorSession {
  EditorSession({
    required this.services,
    required this.shared,
    required void Function() onStylusDetected,
    EditorViewState? initialView,
    ZoomWindowState? initialZoom,
  }) : tools = ToolSettings(
         stylusOnly: services.settings.stylusOnly,
         penButtonErases: services.preferences.penButtonAction == PenButtonAction.eraser,
         holdToStraighten: services.preferences.holdToSnap,
         scribbleToErase: services.preferences.scribbleToErase,
         store: services.settings,
       ) {
    final current = shared.notebook;
    if (current.kind == NotebookKind.canvas) {
      final model = canvas = shared.canvasModel(
        () => SurfaceModel(
          surfaceId: current.id,
          repository: services.strokes,
          elementRepository: services.elements,
          images: services.images,
          reader: services.strokeReader,
          writeBehind: true,
          outlines: services.outlines,
          rasterStore: services.rasterStore,
        ),
      );
      final viewport = canvasViewport = ViewportController();
      final nav = canvasNav = CanvasNavigation(
        viewport: viewport,
        reader: services.strokeReader,
        surfaceId: current.id,
      );
      nav.open(initialView);
      content = _contentFor(model, viewport);
      input = _inputFor(
        model,
        viewport,
        onStylusDetected,
        // Pinches ending near 100 % snap to it.
        kinetic: KineticPan(nav.animator, settle: (f, {required zoomed}) => zoomed && zoom.snap(f)),
      );
      undo = SurfaceUndo(model);
      zoom = DoubleTapZoom(viewport: viewport, animator: nav.animator, home: () => 1);
    } else {
      final doc = this.doc = _openDocument(current, initialView);
      final commands = this.commands = DocumentCommands(
        services: services,
        notebook: () => shared.notebook,
        doc: doc,
        reloadViews: shared.reloadViews,
      );
      shared.attachDocument(doc, commands.reload);
      backgrounds = shared.backgrounds;
      pdfBackgrounds = shared.pdfBackgrounds;
      content = _contentFor(doc.activeModel, doc.pageViewport);
      final pdf = this.pdf = PdfInteraction(doc: doc, tools: tools, info: shared.pdfInfo);
      content.lasso.text = pdf; // The lasso selects PDF text too.
      // A lasso reaches across pages; selections dropped on a page move there.
      content.selection.surfaces = DocumentSelection(doc);
      final animator = docAnimator = ViewportAnimator(doc.viewport);
      doc.beforeJump = animator.stop;
      input = doc.input = _inputFor(
        doc.activeModel,
        doc.pageViewport,
        onStylusDetected,
        // Single pages settle back to the whole page; pinches ending near
        // the page fit snap to it.
        kinetic: KineticPan(
          animator,
          settle: (focal, {required zoomed}) => doc.settleSingle() || (zoomed && zoom.snap(focal)),
        ),
      )..highlightSnap = PdfHighlightSnap(doc: doc, info: shared.pdfInfo);
      // Paste onto the page in the middle of the screen.
      content.beforePasteAtCentre = () => doc.activateAt(doc.viewport.size.center(Offset.zero));
      undo = doc.surfaces;
      zoom = DoubleTapZoom(
        viewport: doc.viewport,
        animator: animator,
        home: () => doc.frameTarget(doc.currentPage)?.scale,
        homeOffsetX: () => doc.frameTarget(doc.currentPage)?.offset.dx,
      );
    }
    gestures.onDoubleTap = zoom.toggle;
    if (initialZoom != null) _restoreZoom(initialZoom);
  }

  final AppServices services;

  /// What this editor shares with other editors of the notebook.
  final SharedNotebook shared;
  final ToolSettings tools;
  final LiveInk live = LiveInk();

  /// Multi-finger taps, long press and right click on the canvas; the
  /// editor sets the callbacks.
  final CanvasGestures gestures = CanvasGestures();

  late final InkInputController input;
  late final ContentTools content;
  late final UndoTarget undo;

  /// Double-tap zoom: page fit (100 % on canvases) ⇄ a closer look.
  late final DoubleTapZoom zoom;

  /// Inserting images (picker, clipboard, drag and drop, camera).
  late final EditorImages images = EditorImages(
    services: services,
    content: content,
    tools: tools,
    activateAt: doc?.activateAt,
  );

  /// The zoom window: writing small through a magnified box.
  late final ZoomWindow zoomWindow = () {
    _zoomCreated = true;
    return ZoomWindow(host: _zoomHost(), input: _zoomInput);
  }();
  bool _zoomCreated = false;

  /// Opens the zoom window (with the pen, unless the highlighter or the
  /// eraser is in hand: the box writes and erases), or closes it.
  void toggleZoomWindow() {
    final zoom = zoomWindow;
    if (!zoom.isOpen) _toolForZoom();
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

  /// Page and web links: finding, following and making them.
  late final EditorLinks links = EditorLinks(this);

  // Infinite canvas: one surface (the shared notebook's).
  SurfaceModel? canvas;
  ViewportController? canvasViewport;

  /// Inertial panning, zoom steps and fit of the canvas.
  CanvasNavigation? canvasNav;

  // Paged notebook: pages laid out as a document.
  DocumentController? doc;
  DocumentCommands? commands;

  /// Page backgrounds: PDF pages and scans (the shared notebook's).
  PageBackgrounds? backgrounds;

  /// Rendered PDF backgrounds (the shared notebook's).
  PdfBackgroundCache? pdfBackgrounds;

  /// Text selection, links and outline of imported PDF pages.
  PdfInteraction? pdf;

  /// Drives the document's inertial scrolling.
  ViewportAnimator? docAnimator;

  /// The viewport input works in: the canvas, or the active page's view.
  ViewportController get viewport => doc?.pageViewport ?? canvasViewport!;

  /// Whether anything was edited (to bump "last edited" and sync on close).
  bool get edited => undo.canUndo || undo.canRedo || (commands?.changed ?? false);

  /// Where the editor is looking, to restore it in a tab later.
  EditorViewState get viewState {
    final doc = this.doc;
    if (doc != null) return doc.viewState;
    final v = canvasViewport!;
    return EditorViewState(scale: v.scale, offset: v.offset, size: v.size);
  }

  DocumentController _openDocument(Notebook notebook, EditorViewState? view) {
    var pages = services.pages.pagesOf(notebook.id);
    if (pages.isEmpty) pages = [services.pages.addFreshPage(notebook)];
    return DocumentController(
      pages: pages,
      strokes: services.strokes,
      elements: services.elements,
      images: services.images,
      outlines: services.outlines,
      flow: PageFlow.parse(services.settings.pageFlow),
      initialPage: view?.page ?? 0,
      initialView: view,
      fit: PageFit.parse(view?.fit),
      models: shared.pages,
    );
  }

  ContentTools _contentFor(SurfaceModel model, ViewportController viewport) => ContentTools(
    model: model,
    viewport: viewport,
    tools: tools,
    live: live,
    clipboard: services.clipboard,
  );

  /// The input controller (and the lasso, shape, text and laser tools it
  /// routes to) for [model] seen through [viewport]. For documents these
  /// are the active page's model and its page viewport, so tools work in
  /// page coordinates and follow the active page.
  InkInputController _inputFor(
    SurfaceModel model,
    ViewportController viewport,
    void Function() onStylusDetected, {
    KineticPan? kinetic,
  }) => InkInputController(
    model: model,
    viewport: viewport,
    tools: tools,
    live: live,
    onStylusDetected: onStylusDetected,
    content: content,
    gestures: gestures,
    kinetic: kinetic,
    samples: openStylusSamples(
      wetInk: () => WetInkStyle.of(live, viewport.scale),
      // Pressing on a selection moves it rather than drawing.
      wetInkNext: () =>
          content.selection.isEmpty ? WetInkStyle.forNextStroke(tools, viewport.scale) : null,
      wetInkView: () => WetInkView.of(viewport, covered: _chromeInsets),
    ),
    penButtonAction: () => services.preferences.penButtonAction,
  );

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
  InkInputController _zoomInput(SurfaceModel model, ZoomBoxViewport view) => InkInputController(
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
  );

  Rect? _zoomPage() {
    final frame = zoomWindow.frame;
    return frame == null ? null : zoomWindow.host.boundsOf(frame.surfaceId);
  }

  /// Keeps document content scrollable clear of the chrome covering
  /// [covered] of the screen, and fits keep canvas content clear of it.
  /// Applied after the frame (it moves the viewport, which notifies).
  void setChromeInsets(EdgeInsets covered) {
    _chromeInsets = covered;
    final doc = this.doc;
    final nav = canvasNav;
    final same = doc != null
        ? doc.insets == covered
        : nav != null && !nav.waitingForInsets && nav.insets == covered;
    if (same) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      doc?.setInsets(covered);
      nav?.setInsets(covered);
    });
  }

  bool _disposed = false;

  /// Screen edges covered by chrome (the low-latency overlay stays clear of them).
  EdgeInsets _chromeInsets = EdgeInsets.zero;

  /// Ends the session: commits a text box still being edited and releases
  /// every surface (shared ones stay with the [shared] notebook).
  void dispose() {
    _disposed = true;
    input.cancelDraw(); // Stops a stroke's or tool's pending timers.
    if (_zoomCreated) zoomWindow.dispose();
    images.dispose();
    content.dispose();
    gestures.dispose();
    canvasNav?.dispose();
    canvasViewport?.dispose();
    docAnimator?.dispose();
    commands?.dispose();
    pdf?.dispose();
    if (doc case final doc?) shared.detachDocument(doc);
    doc?.dispose();
    live.dispose();
    tools.dispose();
  }

  /// The notebook as currently known (it may be renamed while open).
  Notebook get notebook => shared.notebook;
}
