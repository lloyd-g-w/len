import 'package:flutter/material.dart';

import '../../domain/paper.dart';
import 'canvas/canvas_view.dart';
import 'chrome/canvas_guard.dart';
import 'document/add_page_footer.dart';
import 'document/paged_document_view.dart';
import 'editor_session.dart';
import 'links/link_layer.dart';
import 'links/link_taps.dart';
import 'tools/content_layer.dart';
import 'tools/selection_menu.dart';

/// What the chrome floats over: the drawing surface (an infinite canvas or
/// the paged document with its "add page" footer) and the content tools'
/// layer (selection, text editor, laser).
class EditorCanvas extends StatelessWidget {
  const EditorCanvas({
    super.key,
    required this.session,
    required this.paper,
    required this.paperColor,
    required this.focusNode,
    required this.guard,
    required this.chromeInsets,
    required this.onFollowLink,
    this.selectionActions,
  });

  final EditorSession session;

  /// Background of an infinite canvas.
  final Paper paper;
  final PaperColor paperColor;

  /// The editor's keyboard focus, reclaimed when the canvas is touched.
  final FocusNode focusNode;

  /// Blocks the surface while a chrome menu is open.
  final CanvasGuard guard;

  /// Screen edges covered by chrome; menus over the content and the
  /// canvas's zoom pill and fit button avoid them.
  final EdgeInsets chromeInsets;

  /// Follows a planner link to its page.
  final ValueChanged<Paper> onFollowLink;

  /// Commands the editor adds to the lasso selection's menu.
  final List<SelectionExtraAction> Function()? selectionActions;

  @override
  Widget build(BuildContext context) {
    final doc = session.doc;
    return Stack(
      fit: StackFit.expand,
      children: [
        _surface(context),
        Positioned.fill(child: LinkLayer(session: session)),
        if (doc != null)
          AddPageFooter(
            doc: doc,
            onAdd: session.commands!.addPage,
            onAddWithTemplate: () => session.commands!.addPageWithTemplate(context),
          ),
        MediaQuery(
          data: MediaQuery.of(context).copyWith(padding: chromeInsets),
          child: _contentLayer(),
        ),
      ],
    );
  }

  Widget _surface(BuildContext context) {
    final doc = session.doc;
    bool fingersNavigate() => session.tools.fingersNavigate;
    void follow(Offset at) {
      if (session.links.followAt(context, at)) return;
      if (doc?.plannerLinkAt(at) case final planner?) onFollowLink(planner);
    }

    final view = doc != null
        ? PagedDocumentView(
            controller: doc,
            input: session.input,
            live: session.live,
            backgrounds: session.backgrounds,
          )
        : CanvasView(
            model: session.canvas!,
            navigation: session.canvasNav!,
            input: session.input,
            live: session.live,
            paper: paper,
            paperColor: paperColor,
            insets: chromeInsets,
          );
    final surface = LinkTaps(fingersNavigate: fingersNavigate, follow: follow, child: view);
    return Listener(
      // Touching the canvas takes keyboard focus back for the shortcuts,
      // without competing for the pointer.
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (!focusNode.hasFocus) focusNode.requestFocus();
      },
      // While a menu is open, a tap on the canvas only closes it.
      // A hand writing in the zoom window rests on the page: it neither
      // draws nor scrolls there.
      child: ListenableBuilder(
        listenable: Listenable.merge([guard, session.zoomWindow.blocksPage]),
        builder: (context, child) => AbsorbPointer(
          absorbing: guard.blocking || session.zoomWindow.blocksPage.value,
          child: child,
        ),
        child: surface,
      ),
    );
  }

  /// For documents the layer follows the active page (viewport and clip).
  Widget _contentLayer() {
    final doc = session.doc;
    if (doc == null) {
      return ContentLayer(
        content: session.content,
        viewport: session.canvasViewport!,
        tools: session.tools,
        selectionActions: selectionActions,
      );
    }
    return ListenableBuilder(
      listenable: doc, // Notifies when the active page changes.
      builder: (context, _) => ContentLayer(
        content: session.content,
        viewport: doc.pageViewport,
        tools: session.tools,
        pages: [for (final f in doc.layout.frames) f.shift(-doc.pageViewport.origin)],
        selectionActions: selectionActions,
      ),
    );
  }
}
