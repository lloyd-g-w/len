part of 'editor_session.dart';

/// Building an [EditorSession]'s parts: the document, the content tools
/// and the input controller.
extension _EditorSessionParts on EditorSession {
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
    clock: services.clock,
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
    palms: services.palmGuard,
  );
}

/// What [FingerReading] asks of an [EditorSession].
extension _EditorSessionReading on EditorSession {
  /// Whether the page in view (or the canvas) has anything to read: a PDF
  /// or scanned background, planner links, or ink, text boxes or images
  /// (loaded, or stored).
  bool _hasContent() {
    final doc = this.doc;
    final String surfaceId;
    if (doc != null) {
      final page = doc.pages[doc.currentPage];
      if (page.background != null || doc.hasPlannerLinks(doc.currentPage)) return true;
      surfaceId = page.id;
    } else {
      surfaceId = canvas!.surfaceId;
    }
    final model = doc?.activeModel ?? canvas!;
    final loaded =
        model.surfaceId == surfaceId &&
        (model.loadedStrokeCount > 0 || model.loadedElementCount > 0);
    return loaded || services.strokes.hasContent(surfaceId);
  }

  /// Whether something is under way that reading would interrupt: a stroke,
  /// a text box being typed, a selection, the zoom window, presenting with
  /// the laser (a finger points).
  bool _busy() =>
      live.isDrawing ||
      tools.tool == EditorTool.laser ||
      content.text.isEditing ||
      !content.selection.isEmpty ||
      !(pdf?.selection.isEmpty ?? true) ||
      (_zoomCreated && zoomWindow.isOpen);
}
