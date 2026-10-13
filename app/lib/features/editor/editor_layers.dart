import 'package:flutter/material.dart';

import '../../domain/notebook.dart';
import '../../domain/paper.dart';
import '../audio/audio_layer.dart';
import '../audio/notebook_audio.dart';
import '../search/editor/editor_search_controller.dart';
import '../search/editor/editor_search_layer.dart';
import 'canvas/canvas_empty_hint.dart';
import 'chrome/canvas_context_menu.dart';
import 'chrome/canvas_guard.dart';
import 'chrome/editor_chrome.dart';
import 'editor_canvas.dart';
import 'editor_gestures.dart';
import 'editor_session.dart';
import 'images/image_entry_points.dart';
import 'links/link_actions.dart';
import 'pdf/pdf_layer.dart';
import 'split/split_controller.dart';
import 'split/split_drop_highlight.dart';

/// The editor's layers, bottom to top: the surface, PDF text, the empty
/// canvas hint, image drops, audio, the chrome and search, and on top the split view's drop
/// highlight and the canvas context menu.
///
/// A feature that shows something over the surface adds its layer here.
class EditorLayers extends StatelessWidget {
  const EditorLayers({
    super.key,
    required this.session,
    required this.notebook,
    required this.layout,
    required this.focusNode,
    required this.guard,
    required this.audio,
    required this.search,
    required this.chrome,
    required this.onFollowLink,
    required this.onCloseMenu,
    this.split,
    this.menu,
  });

  final EditorSession session;
  final Notebook notebook;
  final ChromeLayout layout;
  final FocusNode focusNode;
  final CanvasGuard guard;
  final NotebookAudio audio;
  final EditorSearchController search;

  /// The top bar, toolbar and page navigator (or the focus mode handle).
  final Widget chrome;
  final ValueChanged<Paper> onFollowLink;

  /// This editor in the split view, if shown in one.
  final ({SplitController controller, SplitPane pane})? split;

  final EditorMenu? menu;
  final VoidCallback onCloseMenu;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: EditorCanvas(
            session: session,
            paper: notebook.paper,
            paperColor: notebook.paperColor,
            focusNode: focusNode,
            guard: guard,
            chromeInsets: layout.covered,
            onFollowLink: onFollowLink,
            selectionActions: () => [linkSelectionAction(context, session)],
          ),
        ),
        if (session.pdf case final pdf?) Positioned.fill(child: PdfLayer(interaction: pdf)),
        if (session.canvas != null)
          Positioned.fill(
            child: Padding(
              padding: layout.covered,
              child: CanvasEmptyHint(
                reader: session.services.strokeReader,
                surfaceId: notebook.id,
                edits: session.undo,
                darkPaper: notebook.paperColor.isDark,
              ),
            ),
          ),
        Positioned.fill(child: ImageDropTarget(images: session.images)),
        Positioned.fill(
          child: AudioLayer(
            audio: audio,
            session: session,
            chromeInsets: layout.floatingInsets,
            canvasPaper: notebook.paperColor,
          ),
        ),
        Positioned.fill(child: chrome),
        Positioned.fill(
          child: EditorSearchLayer(
            controller: search,
            covered: layout.covered,
            onClose: focusNode.requestFocus,
          ),
        ),
        if (split case final split?)
          Positioned.fill(
            child: SplitDropHighlight(split: split.controller, pane: split.pane),
          ),
        if (menu case final menu?)
          Positioned.fill(
            child: CanvasContextMenu(at: menu.at, actions: menu.actions, onDismiss: onCloseMenu),
          ),
      ],
    );
  }
}
