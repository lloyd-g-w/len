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
}
