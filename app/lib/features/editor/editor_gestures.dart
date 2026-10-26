import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/paper.dart';
import 'chrome/canvas_context_menu.dart';
import 'chrome/gesture_hud.dart';
import 'clipboard/paste_peek.dart';
import 'editor_session.dart';
import 'links/link_actions.dart';

/// The canvas context menu: where it is open and what it offers.
typedef EditorMenu = ({Offset at, List<CanvasAction> actions});

/// The canvas context menu for a long press or right click at [at]: a
/// link there first, then [canvasActions], Paste here only if [mayPaste]
/// finds something to paste. Null when that selects a word of PDF text
/// instead.
Future<EditorMenu?> canvasMenuAt(
  BuildContext context,
  EditorSession session,
  Offset at, {
  required void Function(Paper target) onFollowLink,
  ClipboardPeek? peek,
}) async {
  if (session.pdf?.selectWordAt(at) ?? false) return null;
  final paste = await mayPaste(session.services.clipboard, peek: peek);
  if (!context.mounted) return null;
  final actions = canvasActions(
    session,
    at,
    onFollowLink: onFollowLink,
    onPaste: paste ? () => unawaited(session.images.paste(context, screen: at)) : null,
  );
  if (openLinkAction(context, session, at) case final link?) actions.insert(0, link);
  return (at: at, actions: actions);
}

/// The entries of the canvas context menu for a long press at [screen]:
/// paste there ([onPaste], what Ctrl+V would paste; none without it),
/// select everything on the page (or in view) and add a text box there.
/// Content only: page commands live in ⋯ → Page (UX_AUDIT R9-3).
List<CanvasAction> canvasActions(
  EditorSession session,
  Offset screen, {
  void Function(Paper target)? onFollowLink,
  VoidCallback? onPaste,
}) {
  final doc = session.doc;
  // Act on the page under the finger.
  doc?.activateAt(screen);
  final link = doc?.plannerLinkAt(screen);
  final content = session.content;
  final viewport = session.viewport;
  final world = viewport.toWorld(screen);
  return [
    if (link != null && onFollowLink != null)
      CanvasAction(Symbols.event_rounded, 'Go to ${link.period}', () => onFollowLink(link)),
    if (onPaste != null) CanvasAction(Symbols.content_paste_rounded, 'Paste here', onPaste),
    CanvasAction(
      Symbols.select_all_rounded,
      doc == null ? 'Select all in view' : 'Select all on page',
      () => content.selectAllIn(doc?.pageViewport.contentBounds ?? viewport.visibleWorld),
    ),
    CanvasAction(Symbols.text_fields_rounded, 'Add text here', () => content.addTextAt(world)),
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
    hud.show(Symbols.undo_rounded, could ? 'Undo' : 'Nothing to undo', counts: could);
  } else if (fingers == 3) {
    final could = undo.canRedo;
    if (could) undo.redo();
    hud.show(Symbols.redo_rounded, could ? 'Redo' : 'Nothing to redo', counts: could);
  }
}
