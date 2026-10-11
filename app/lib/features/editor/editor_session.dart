import 'dart:ui';

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
import '../../sync/sync_engine.dart';
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
import 'pdf/pdf_page_info.dart';
import 'stickers/editor_stickers.dart';
import 'tabs/open_notebooks.dart';

/// The engine side of one open editor: tool settings, input routing, the
/// content tools, undo, and either one infinite-canvas surface or a paged
/// document. Owns (and disposes) all of it; widgets only read it.
class EditorSession {
  EditorSession({
    required this.services,
    required Notebook Function() notebook,
    required void Function() onStylusDetected,
    EditorViewState? initialView,
  }) : _notebook = notebook,
       tools = ToolSettings(stylusOnly: services.settings.stylusOnly, store: services.settings) {
    final current = notebook();
    if (current.kind == NotebookKind.canvas) {
      final model = canvas = SurfaceModel(
        surfaceId: current.id,
        repository: services.strokes,
        elementRepository: services.elements,
        images: services.images,
        reader: services.strokeReader,
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
      undo = SurfaceUndo(model)..onStep = () => onSurfaceEdited?.call(current.id);
      model.onCommit = () => onSurfaceEdited?.call(current.id);
      zoom = DoubleTapZoom(viewport: viewport, animator: nav.animator, home: () => 1);
    } else {
      final doc = this.doc = _openDocument(current, initialView);
      commands = DocumentCommands(services: services, notebook: notebook, doc: doc);
      final backgrounds = this.backgrounds = PdfBackgroundCache(
        blobs: services.blobs,
        fetch: services.sync.fetchBlob,
      );
      content = _contentFor(doc.activeModel, doc.pageViewport);
      final pdf = this.pdf = PdfInteraction(
        doc: doc,
        tools: tools,
        source: PdfrxInfoSource(backgrounds.renderer, services.blobs),
      );
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
      doc.surfaces.onEdited = (pageId) => onSurfaceEdited?.call(pageId);
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
  final Notebook Function() _notebook;
  final ToolSettings tools;
  final LiveInk live = LiveInk();

  /// Called with the surface (page or canvas) of every edit made in this
  /// editor, including undo and redo (split view keeps a second view of
  /// the same notebook current with it).
  void Function(String surfaceId)? onSurfaceEdited;

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

  // Infinite canvas: one surface.
  SurfaceModel? canvas;
  ViewportController? canvasViewport;

  /// Inertial panning, zoom steps, fit, minimap of the canvas.
  CanvasNavigation? canvasNav;

  // Paged notebook: pages laid out as a document.
  DocumentController? doc;
  DocumentCommands? commands;
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
      flow: PageFlow.parse(services.settings.pageFlow),
      initialPage: view?.page ?? 0,
      initialView: view,
      fit: PageFit.parse(view?.fit),
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
      lowLatency: () => services.preferences.lowLatencyInk,
      wetInk: () => WetInkStyle.of(live, viewport.scale),
    ),
    penButtonAction: () => services.preferences.penButtonAction,
  );

  /// Reloads what another device changed: the page list, and the strokes
  /// of surfaces that are open.
  void applyRemoteChanges(RemoteChanges changes) {
    final doc = this.doc;
    final notebookId = notebook.id;
    services.images.retryMissing(); // Image blobs may be on the server now.
    if (doc != null && changes.pagesOfNotebooks.contains(notebookId)) {
      // Every page deleted elsewhere: start a fresh one, as opening does.
      if (services.pages.pagesOf(notebookId).isEmpty) {
        services.pages.addPage(notebookId, paper: notebook.paper);
      }
      commands!.reload();
      backgrounds?.retryMissing(); // New pages may bring new PDFs.
      pdf?.info.retry();
    }
    for (final surfaceId in changes.strokeSurfaces) {
      if (surfaceId == canvas?.surfaceId) canvas!.reload();
      doc?.surfaces.reload(surfaceId);
    }
  }

  /// Ends the session: commits a text box still being edited and releases
  /// every surface.
  void dispose() {
    input.cancelDraw(); // Stops a stroke's or tool's pending timers.
    images.dispose();
    stickers.dispose();
    content.dispose();
    gestures.dispose();
    canvas?.dispose();
    canvasNav?.dispose();
    canvasViewport?.dispose();
    docAnimator?.dispose();
    commands?.dispose();
    pdf?.dispose();
    doc?.dispose();
    backgrounds?.dispose();
    live.dispose();
    tools.dispose();
  }

  /// The notebook as currently known (it may be renamed while open).
  Notebook get notebook => _notebook();
}
