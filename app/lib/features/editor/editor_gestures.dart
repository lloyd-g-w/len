import 'package:flutter/material.dart';

import '../../domain/paper.dart';
import '../../ink/tool_settings.dart';
import '../../ink/tools/text_tool.dart';
import 'chrome/canvas_context_menu.dart';
import 'chrome/gesture_hud.dart';
import 'document/page_overview.dart';
import 'editor_session.dart';

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
      CanvasAction(
        Icons.event_rounded,
        'Go to ${PlannerDates.describe(link.style.period!, link.date!)}',
        () => onFollowLink(link),
      ),
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
      content.text.create(
        world,
        width: TextTool.newBoxWidth / viewport.scale,
        style: tools.textStyle,
      );
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

/// Two-finger tap undoes, three-finger tap redoes (each if enabled in the
/// settings), with a brief HUD saying what happened.
void runMultiFingerTap(EditorSession session, int fingers, HudController hud) {
  final prefs = session.services.preferences;
  final undo = session.undo;
  if (fingers == 2 && prefs.twoFingerTapUndo) {
    final could = undo.canUndo;
    if (could) undo.undo();
    hud.show(Icons.undo_rounded, could ? 'Undo' : 'Nothing to undo', counts: could);
  } else if (fingers == 3 && prefs.threeFingerTapRedo) {
    final could = undo.canRedo;
    if (could) undo.redo();
    hud.show(Icons.redo_rounded, could ? 'Redo' : 'Nothing to redo', counts: could);
  }
}
