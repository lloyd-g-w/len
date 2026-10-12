import 'package:flutter/material.dart';

import '../../domain/paper.dart';
import '../../ink/tool_settings.dart';
import 'chrome/canvas_context_menu.dart';
import 'chrome/gesture_hud.dart';
import 'document/page_overview.dart';
import 'editor_session.dart';
import 'links/link_actions.dart';

/// The canvas context menu: where it is open and what it offers.
typedef EditorMenu = ({Offset at, List<CanvasAction> actions});

/// The canvas context menu for a long press or right click at [at]: a
/// link there first, then [canvasActions]. Null when that selects a word of
/// PDF text instead.
EditorMenu? canvasMenuAt(
  BuildContext context,
  EditorSession session,
  Offset at, {
  required void Function(Paper target) onFollowLink,
}) {
  if (session.pdf?.selectWordAt(at) ?? false) return null;
  final doc = session.doc;
  final actions = canvasActions(
    session,
    at,
    bookmarked: doc?.activePageData.bookmarked ?? false,
    onPageCommand: (c) => session.commands!.run(context, c, doc!.activePageData),
    onFollowLink: onFollowLink,
  );
  if (openLinkAction(context, session, at) case final link?) actions.insert(0, link);
  return (at: at, actions: actions);
}

/// The entries of the canvas context menu for a long press at [screen]:
/// paste there, select everything on the page (or in view), add a text box
/// there and, in paged notebooks, a few page commands.
List<CanvasAction> canvasActions(
  EditorSession session,
  Offset screen, {
  required void Function(PageCommand command) onPageCommand,
  required bool bookmarked,
  void Function(Paper target)? onFollowLink,
}) {
  final doc = session.doc;
  // Act on the page under the finger.
  doc?.activateAt(screen);
  final link = doc?.plannerLinkAt(screen);
  final content = session.content;
  final viewport = session.viewport;
  final world = viewport.toWorld(screen);
  final clipboard = content.selection.clipboard;
  return [
    if (link != null && onFollowLink != null)
      CanvasAction(Icons.event_rounded, 'Go to ${link.period}', () => onFollowLink(link)),
    if (!clipboard.isEmpty)
      CanvasAction(Icons.content_paste_rounded, 'Paste here', () {
        session.tools.tool = EditorTool.lasso;
        content.selection.paste(world);
      }),
    CanvasAction(
      Icons.select_all_rounded,
      doc == null ? 'Select all in view' : 'Select all on page',
      () => content.selectAllIn(doc?.pageViewport.contentBounds ?? viewport.visibleWorld),
    ),
    CanvasAction(Icons.text_fields_rounded, 'Add text here', () {
      final tools = session.tools;
      tools.tool = EditorTool.text;
      content.textTool.startBox(world);
    }),
    if (doc != null) ...[
      CanvasAction(
        Icons.add_rounded,
        'Add page after',
        () => onPageCommand(PageCommand.insertAfter),
        dividerBefore: true,
      ),
      CanvasAction(
        bookmarked ? Icons.bookmark_remove_rounded : Icons.bookmark_add_outlined,
        bookmarked ? 'Remove bookmark' : 'Bookmark page',
        () => onPageCommand(PageCommand.bookmark),
      ),
      CanvasAction(
        Icons.grid_on_rounded,
        'Change template…',
        () => onPageCommand(PageCommand.template),
      ),
    ],
  ];
}

/// Two-finger tap undoes, three-finger tap redoes (if enabled in the
/// settings), with a brief HUD saying what happened.
void runMultiFingerTap(EditorSession session, int fingers, HudController hud) {
  if (!session.services.preferences.fingerTapUndo) return;
  final undo = session.undo;
  if (fingers == 2) {
    final could = undo.canUndo;
    if (could) undo.undo();
    hud.show(Icons.undo_rounded, could ? 'Undo' : 'Nothing to undo', counts: could);
  } else if (fingers == 3) {
    final could = undo.canRedo;
    if (could) undo.redo();
    hud.show(Icons.redo_rounded, could ? 'Redo' : 'Nothing to redo', counts: could);
  }
}
