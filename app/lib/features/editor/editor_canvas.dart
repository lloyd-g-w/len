import 'package:flutter/material.dart';

import '../../domain/paper.dart';
import 'canvas/canvas_view.dart';
import 'chrome/canvas_guard.dart';
import 'document/add_page_footer.dart';
import 'document/paged_document_view.dart';
import 'document/planner_link_taps.dart';
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
    required this.paperColor,
    required this.focusNode,
    required this.guard,
    required this.chromeInsets,
    required this.onFollowLink,
  });

  final EditorSession session;

  /// Background of an infinite canvas.
  final PaperStyle paper;
  final PaperColor paperColor;

  /// The editor's keyboard focus, reclaimed when the canvas is touched.
  final FocusNode focusNode;

  /// Blocks the surface while a chrome menu is open.
  final CanvasGuard guard;

  /// Screen edges covered by chrome; menus over the content and the
  /// canvas's zoom pill and minimap avoid them.
  final EdgeInsets chromeInsets;

  /// Follows a planner link to its page.
  final ValueChanged<Paper> onFollowLink;

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
    bool fingersNavigate() => session.tools.stylusOnly ?? false;
    final surface = doc != null
        ? PlannerLinkTaps(
            doc: doc,
            fingersNavigate: fingersNavigate,
            onFollow: onFollowLink,
            child: PagedDocumentView(
              controller: doc,
              input: session.input,
              live: session.live,
              backgrounds: session.backgrounds,
              fingersNavigate: fingersNavigate,
            ),
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
