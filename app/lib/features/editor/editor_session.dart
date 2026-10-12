import 'package:flutter/widgets.dart';

import '../../app_services.dart';
import '../../domain/notebook.dart';
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
import 'document/page_fit.dart';
import 'document/undo_target.dart';
import 'double_tap_zoom.dart';
import 'images/editor_images.dart';
import 'links/editor_links.dart';
import 'pdf/pdf_interaction.dart';
import 'shared/shared_notebook.dart';
import 'stickers/editor_stickers.dart';
import 'tabs/open_notebooks.dart';

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
  }) : tools = ToolSettings(stylusOnly: services.settings.stylusOnly, store: services.settings) {
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
        ),
      );
      final viewport = canvasViewport = ViewportController();
      final nav = canvasNav = CanvasNavigation(
        viewport: viewport,
        reader: services.strokeReader,
        surfaceId: current.id,
        showMinimap: services.settings.canvasMinimap,
        onMinimapChanged: (show) => services.settings.canvasMinimap = show,
      );
      nav.open(initialView);
      content = _contentFor(model, viewport);
      input = _inputFor(model, viewport, onStylusDetected, kinetic: nav.kinetic);
      undo = SurfaceUndo(model);
      zoom = DoubleTapZoom(viewport: viewport, animator: nav.animator, home: () => 1);
    } else {
      final doc = this.doc = _openDocument(current, initialView);
      final commands = this.commands = DocumentCommands(
        services: services,
        notebook: () => shared.notebook,
        doc: doc,
      );
      shared.attachDocument(doc, commands.reload);
      backgrounds = shared.backgrounds;
      content = _contentFor(doc.activeModel, doc.pageViewport);
      final pdf = this.pdf = PdfInteraction(doc: doc, tools: tools, info: shared.pdfInfo);
      content.selectText = pdf.tool;
      final animator = docAnimator = ViewportAnimator(doc.viewport);
      doc.beforeJump = animator.stop;
      input = doc.input = _inputFor(
        doc.activeModel,
        doc.pageViewport,
        onStylusDetected,
        // Continuous scrolling glides on; single pages turn instead.
        kinetic: KineticPan(animator, enabled: () => doc.flow == PageFlow.continuous),
      );
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

  /// Page and web links: finding, following and making them.
  late final EditorLinks links = EditorLinks(this);

  /// The sticker panel, inserting stickers and saving new ones.
  late final EditorStickers stickers = EditorStickers(this);

  // Infinite canvas: one surface (the shared notebook's).
  SurfaceModel? canvas;
  ViewportController? canvasViewport;

  /// Inertial panning, zoom steps, fit, minimap of the canvas.
  CanvasNavigation? canvasNav;

  // Paged notebook: pages laid out as a document.
  DocumentController? doc;
  DocumentCommands? commands;

  /// Rendered PDF backgrounds (the shared notebook's).
  PdfBackgroundCache? backgrounds;

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
    if (pages.isEmpty) pages = [services.pages.addPage(notebook.id, paper: notebook.paper)];
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
    images.dispose();
    stickers.dispose();
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
