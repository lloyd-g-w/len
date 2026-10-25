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
import 'finger_reading.dart';
import 'images/editor_images.dart';
import 'links/editor_links.dart';
import 'live_ink/live_ink_relay.dart';
import 'live_ink/pointer_relay.dart';
import 'pdf/pdf_highlight_snap.dart';
import 'pdf/pdf_interaction.dart';
import 'pen/slot_counts.dart';
import 'shared/shared_notebook.dart';
import 'tabs/open_notebooks.dart';
import 'zoom/zoom_box_viewport.dart';
import 'zoom/zoom_host.dart';
import 'zoom/zoom_hosts.dart';
import 'zoom/zoom_window.dart';

part 'editor_session_parts.dart';
part 'editor_session_zoom.dart';

/// The engine side of one open editor: tool settings, input routing, the
/// content tools, undo, and either one infinite-canvas surface or a paged
/// document. Owns (and disposes) all of it; widgets only read it.
///
/// The surfaces' models, their undo history and the PDF caches belong to
/// the [shared] notebook (another view of the same notebook uses the same
/// ones); this session only holds them.
class EditorSession with _EditorSessionZoom {
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
    applySlotCounts(tools, services.preferences);
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
      undo = EditingUndo(SurfaceUndo(model), content.text, curve: content.shape.curve);
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
      // Text boxes flow on across pages.
      content.flows = commands.flows;
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
      undo = EditingUndo(doc.surfaces, content.text, curve: content.shape.curve);
      zoom = DoubleTapZoom(
        viewport: doc.viewport,
        animator: animator,
        home: () => doc.frameTarget(doc.currentPage)?.scale,
        homeOffsetX: () => doc.frameTarget(doc.currentPage)?.offset.dx,
      );
    }
    gestures.onDoubleTap = zoom.toggle;
    relay = LiveInkRelay(
      live: live,
      events: input.events,
      send: (data) => services.sync.rooms.send(shared.id, data),
      anyoneThere: () => services.sync.rooms.othersIn(shared.id).isNotEmpty,
      presence: services.sync.rooms,
      members: () => [for (final m in services.sync.rooms.othersIn(shared.id)) m.connection],
    );
    pointerRelay = PointerRelay(
      events: input.events,
      laser: content.laser,
      surface: () => content.model.surfaceId,
      locate: doc?.pagePointOf,
      send: (data) => services.sync.rooms.send(shared.id, data),
      presence: shared.othersHere,
      anyoneThere: () => shared.othersHere.value,
    );
    if (initialZoom != null) _restoreZoom(initialZoom); // Attaches to [relay].
    content.text
      ..undo = undo.undo
      ..redo = undo.redo;
    reading = FingerReading(tools: tools, hasContent: _hasContent, busy: _busy);
    input.events.contact = reading.wrote;
    commands?.onBlankPage = reading.write;
    content.selection.addListener(_onSelection);
    // Edits (the undo history moving) make versions (docs/ARCHITECTURE.md,
    // "Version history").
    undo.addListener(_onEdited);
  }

  void _onEdited() => services.versionRecorder.noteEdit(shared.id);

  /// Something selected while reading (pasted, inserted, all selected)
  /// writes: a finger moves it rather than scrolling.
  void _onSelection() {
    if (!content.selection.isEmpty) reading.write();
  }

  @override
  final AppServices services;

  /// What this editor shares with other editors of the notebook.
  @override
  final SharedNotebook shared;
  @override
  final ToolSettings tools;
  @override
  final LiveInk live = LiveInk();

  /// Multi-finger taps, long press and right click on the canvas; the
  /// editor sets the callbacks.
  final CanvasGestures gestures = CanvasGestures();

  /// Reading while fingers draw (R20-6): one finger scrolls until a tool
  /// is chosen; the editor calls [FingerReading.open] once shown.
  late final FingerReading reading;

  late final InkInputController input;

  /// Shows the stroke being written here to other devices in the notebook.
  @override
  late final LiveInkRelay relay;

  /// Shows where this editor points (hover, laser) to other devices.
  late final PointerRelay pointerRelay;
  late final ContentTools content;
  late final EditingUndo undo;

  /// Double-tap zoom: page fit (100 % on canvases) ⇄ a closer look.
  late final DoubleTapZoom zoom;

  /// Inserting images (picker, clipboard, drag and drop, camera).
  late final EditorImages images = EditorImages(
    services: services,
    notebookId: shared.notebook.id,
    content: content,
    tools: tools,
    activateAt: doc?.activateAt,
    reveal: _reveal,
  );

  /// Shows page [id] (making it the edited one), or point [at] of the
  /// canvas [id]; false if there is no such page (or canvas).
  bool _reveal(String id, Offset at) {
    if (doc case final doc?) {
      final index = doc.pages.indexWhere((p) => p.id == id);
      if (index < 0) return false;
      doc.goToPage(index);
      return true;
    }
    if (id != canvas!.surfaceId) return false;
    final nav = canvasNav!;
    if (!nav.visibleArea.contains(at)) nav.centreOn(at, animate: false);
    return true;
  }

  /// Page and web links: finding, following and making them.
  late final EditorLinks links = EditorLinks(this);

  // Infinite canvas: one surface (the shared notebook's).
  @override
  SurfaceModel? canvas;
  @override
  ViewportController? canvasViewport;

  /// Inertial panning, zoom steps and fit of the canvas.
  @override
  CanvasNavigation? canvasNav;

  // Paged notebook: pages laid out as a document.
  @override
  DocumentController? doc;
  @override
  DocumentCommands? commands;

  /// Page backgrounds: PDF pages and scans (the shared notebook's).
  PageBackgrounds? backgrounds;

  /// Rendered PDF backgrounds (the shared notebook's).
  PdfBackgroundCache? pdfBackgrounds;

  /// Text selection, links and outline of imported PDF pages.
  PdfInteraction? pdf;

  /// Drives the document's inertial scrolling.
  @override
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

  /// Screen edges covered by chrome, as last laid out.
  EdgeInsets get chromeInsets => _chromeInsets;

  /// Screen edges covered by chrome (the low-latency overlay stays clear of them).
  @override
  EdgeInsets _chromeInsets = EdgeInsets.zero;

  /// Ends the session: commits a text box still being edited and releases
  /// every surface (shared ones stay with the [shared] notebook).
  void dispose() {
    _disposed = true;
    reading.dispose();
    content.selection.removeListener(_onSelection);
    undo.removeListener(_onEdited);
    input.cancelDraw(); // Stops a stroke's or tool's pending timers.
    relay.dispose();
    pointerRelay.dispose();
    if (_zoomCreated) zoomWindow.dispose();
    images.dispose();
    undo.dispose();
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
  @override
  Notebook get notebook => shared.notebook;
}
