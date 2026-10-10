import 'package:flutter/material.dart';

import '../../domain/paper.dart';
import '../../ink/ink_surface.dart';
import 'chrome/canvas_guard.dart';
import 'document/add_page_footer.dart';
import 'document/paged_document_view.dart';
import 'editor_session.dart';
import 'tools/content_layer.dart';

/// What the chrome floats over: the drawing surface (an infinite canvas or
/// the paged document with its "add page" footer) and the content tools'
/// layer (selection, text editor, laser).
class EditorCanvas extends StatelessWidget {
  const EditorCanvas({
    super.key,
    required this.session,
    required this.paper,
    required this.focusNode,
    required this.guard,
    required this.chromeInsets,
  });

  final EditorSession session;

  /// Background of an infinite canvas.
  final PaperStyle paper;

  /// The editor's keyboard focus, reclaimed when the canvas is touched.
  final FocusNode focusNode;

  /// Blocks the surface while a chrome menu is open.
  final CanvasGuard guard;

  /// Screen edges covered by chrome; menus over the content avoid them.
  final EdgeInsets chromeInsets;

  @override
  Widget build(BuildContext context) {
    final doc = session.doc;
    return Stack(
      fit: StackFit.expand,
      children: [
        _surface(),
        if (doc != null) AddPageFooter(doc: doc, onAdd: session.commands!.addPage),
        MediaQuery(
          data: MediaQuery.of(context).copyWith(padding: chromeInsets),
          child: _contentLayer(),
        ),
      ],
    );
  }

  Widget _surface() {
    final doc = session.doc;
    final surface = doc != null
        ? PagedDocumentView(
            controller: doc,
            input: session.input,
            live: session.live,
            backgrounds: session.backgrounds,
            fingersNavigate: () => session.tools.stylusOnly ?? false,
          )
        : InkSurface(
            model: session.canvas!,
            viewport: session.canvasViewport!,
            input: session.input,
            live: session.live,
            paper: paper,
          );
    return Listener(
      // Touching the canvas takes keyboard focus back for the shortcuts,
      // without competing for the pointer.
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (!focusNode.hasFocus) focusNode.requestFocus();
      },
      // While a menu is open, a tap on the canvas only closes it.
      child: ListenableBuilder(
        listenable: guard,
        builder: (context, child) => AbsorbPointer(absorbing: guard.blocking, child: child),
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
      );
    }
    return ListenableBuilder(
      listenable: doc, // Notifies when the active page changes.
      builder: (context, _) => ContentLayer(
        content: session.content,
        viewport: doc.pageViewport,
        tools: session.tools,
        page: doc.pageViewport.contentBounds,
      ),
    );
  }
}
