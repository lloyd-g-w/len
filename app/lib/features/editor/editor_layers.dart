import 'package:flutter/material.dart';

import '../../domain/notebook.dart';
import '../../domain/paper.dart';
import '../../ui/app_theme.dart';
import '../audio/audio_layer.dart';
import '../audio/notebook_audio.dart';
import '../search/editor/editor_search_controller.dart';
import '../search/editor/editor_search_layer.dart';
import 'canvas/canvas_empty_hint.dart';
import 'canvas/canvas_minimap.dart';
import 'chrome/canvas_context_menu.dart';
import 'chrome/canvas_guard.dart';
import 'chrome/chrome_layout.dart';
import 'editor_canvas.dart';
import 'editor_gestures.dart';
import 'editor_session.dart';
import 'images/image_entry_points.dart';
import 'links/link_actions.dart';
import 'pdf/pdf_layer.dart';
import 'split/split_controller.dart';
import 'split/split_drop_highlight.dart';
import 'zoom/zoom_box.dart';
import 'zoom/zoom_frame_overlay.dart';

/// The editor's layers, bottom to top: the surface, PDF text, the zoom
/// window's frame, the empty canvas hint, image drops, audio, the
/// canvas's minimap, the zoom window's box, the chrome and search, and on top the split view's drop
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
    this.onDrop,
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

  /// Files dropped on this editor (see [ImageDropTarget.onDrop]).
  final VoidCallback? onDrop;

  /// This editor in the split view, if shown in one.
  final ({SplitController controller, SplitPane pane})? split;

  final EditorMenu? menu;
  final VoidCallback onCloseMenu;

  /// The canvas's minimap, in the bottom-right corner clear of the chrome
  /// (and of the audio strip); in focus mode only when kept there.
  Widget? _minimap() {
    final nav = session.canvasNav;
    final model = session.canvas;
    final prefs = session.services.preferences;
    if (nav == null || model == null || !prefs.canvasMinimap) return null;
    final covered = layout.covered;
    return ValueListenableBuilder(
      valueListenable: audio.stripHeight,
      builder: (context, strip, _) {
        final screen = MediaQuery.sizeOf(context);
        final free = covered.deflateSize(screen);
        return Padding(
          padding: EdgeInsets.fromLTRB(
            layout.safe.left + Gaps.md,
            covered.top + Gaps.md,
            layout.safe.right + Gaps.md,
            covered.bottom + strip + Gaps.md,
          ),
          child: Align(
            alignment: Alignment.bottomRight,
            child: CanvasMinimap(
              navigation: nav,
              model: model,
              live: session.live,
              paperColor: notebook.paperColor,
              size: minimapSize(free, phone: layout.phone),
              visible: !layout.focus,
              onHide: () => prefs.canvasMinimap = false,
            ),
          ),
        );
      },
    );
  }

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
        if (session.zoomWindow.isOpen)
          // It moves with every frame of a scroll: laid out and repainted
          // alone, not with the editor.
          Positioned.fill(
            child: RepaintBoundary(child: ZoomFrameOverlay(zoom: session.zoomWindow)),
          ),
        if (session.canvas != null)
          Positioned.fill(
            child: Padding(
              padding: layout.covered,
              child: CanvasEmptyHint(
                reader: session.services.strokeReader,
                surfaceId: notebook.id,
                edits: session.undo,
                tools: session.tools,
                darkPaper: notebook.paperColor.isDark,
              ),
            ),
          ),
        Positioned.fill(
          child: ImageDropTarget(images: session.images, onDrop: onDrop),
        ),
        Positioned.fill(
          child: AudioLayer(
            audio: audio,
            session: session,
            chromeInsets: layout.covered,
            // Focus mode hides the top bar: the recording controls dock at
            // the bottom then, as on phones.
            compactBar: layout.compactBar || layout.focus,
            canvasPaper: notebook.paperColor,
          ),
        ),
        if (_minimap() case final minimap?) Positioned.fill(child: minimap),
        if (session.zoomWindow.isOpen)
          Positioned(
            left: 0,
            right: 0,
            top: layout.zoomBoxAtTop ? layout.zoomBoxTop : null,
            bottom: layout.zoomBoxAtTop ? null : layout.zoomBoxBottom,
            height: layout.zoomBox,
            child: RepaintBoundary(
              child: ZoomBox(
                atTop: layout.zoomBoxAtTop,
                session: session,
                padding: EdgeInsets.only(left: layout.safe.left, right: layout.safe.right),
              ),
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
