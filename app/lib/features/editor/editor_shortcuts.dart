import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ink/tool_settings.dart';
import '../search/editor/editor_search_controller.dart';
import '../search/editor/editor_search_layer.dart';
import 'canvas/canvas_shortcuts.dart';
import 'document/page_fit.dart';
import 'editor_session.dart';
import 'pdf/pdf_layer.dart';
import 'tabs/open_notebooks.dart';
import 'tools/content_shortcuts.dart';

/// Wraps a single-key shortcut so it doesn't fire while text is edited.
VoidCallback unlessTyping(VoidCallback action) => () {
  // The focus node belongs to a Focus widget inside the EditableText.
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused != null &&
      (focused.widget is EditableText ||
          focused.findAncestorWidgetOfExactType<EditableText>() != null)) {
    return;
  }
  action();
};

const _digitKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
];

/// The editor's keyboard shortcuts: undo/redo, tools, quick colours and
/// widths, selection, focus mode and tabs, plus canvas navigation (zoom,
/// fit, Home = back to start) or page navigation (arrows, Page Up/Down,
/// Home = first page, End = last page).
Map<ShortcutActivator, VoidCallback> editorShortcuts(
  EditorSession session, {
  required VoidCallback toggleFocus,
  VoidCallback? nextTab,
  VoidCallback? previousTab,
  VoidCallback? closeTab,
  VoidCallback? paste,
  VoidCallback? pastePlain,
}) {
  final undo = session.undo;
  final tools = session.tools;
  return {
    for (final mod in [(control: true, meta: false), (control: false, meta: true)]) ...{
      SingleActivator(LogicalKeyboardKey.keyZ, control: mod.control, meta: mod.meta): undo.undo,
      SingleActivator(LogicalKeyboardKey.keyZ, control: mod.control, meta: mod.meta, shift: true):
          undo.redo,
      SingleActivator(LogicalKeyboardKey.period, control: mod.control, meta: mod.meta): toggleFocus,
      SingleActivator(LogicalKeyboardKey.keyW, control: mod.control, meta: mod.meta): ?closeTab,
    },
    const SingleActivator(LogicalKeyboardKey.keyY, control: true): undo.redo,
    const SingleActivator(LogicalKeyboardKey.f11): toggleFocus,
    const SingleActivator(LogicalKeyboardKey.tab, control: true): ?nextTab,
    const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true): ?previousTab,
    const SingleActivator(LogicalKeyboardKey.keyP): unlessTyping(() => tools.tool = EditorTool.pen),
    const SingleActivator(LogicalKeyboardKey.keyH): unlessTyping(
      () => tools.tool = EditorTool.highlighter,
    ),
    const SingleActivator(LogicalKeyboardKey.keyE): unlessTyping(
      () => tools.tool = EditorTool.eraser,
    ),
    // 1–6: quick colours of the pen / highlighter; [ and ]: thinner / thicker.
    // (Shift+1 and 0 belong to the canvas shortcuts.)
    for (final (i, key) in _digitKeys.indexed)
      SingleActivator(key): unlessTyping(() => tools.selectColor(i)),
    const SingleActivator(LogicalKeyboardKey.bracketLeft): unlessTyping(() => tools.stepWidth(-1)),
    const SingleActivator(LogicalKeyboardKey.bracketRight): unlessTyping(() => tools.stepWidth(1)),
    ...contentShortcuts(session.content, tools, unlessTyping, paste: paste, pastePlain: pastePlain),
    if (session.canvasNav case final nav?) ...canvasShortcuts(nav, unlessTyping),
    if (session.doc case final doc?) ...{
      for (final key in [LogicalKeyboardKey.pageDown, LogicalKeyboardKey.arrowRight])
        SingleActivator(key): unlessTyping(() => doc.scrollToPage(doc.currentPage + 1)),
      for (final key in [LogicalKeyboardKey.pageUp, LogicalKeyboardKey.arrowLeft])
        SingleActivator(key): unlessTyping(() => doc.scrollToPage(doc.currentPage - 1)),
      const SingleActivator(LogicalKeyboardKey.home): unlessTyping(() => doc.scrollToPage(0)),
      const SingleActivator(LogicalKeyboardKey.end): unlessTyping(
        () => doc.scrollToPage(doc.pages.length - 1),
      ),
      // Page zoom: 0 automatic, Shift+1 whole page, Shift+2 page width.
      const SingleActivator(LogicalKeyboardKey.digit0): unlessTyping(
        () => doc.setFit(PageFit.auto),
      ),
      const SingleActivator(LogicalKeyboardKey.digit1, shift: true): unlessTyping(
        () => doc.setFit(PageFit.page),
      ),
      const SingleActivator(LogicalKeyboardKey.digit2, shift: true): unlessTyping(
        () => doc.setFit(PageFit.width),
      ),
    },
  };
}

/// Everything the editor screen binds: [editorShortcuts] (with tab
/// switching when it shows [tabs]), F5 [present] (focus mode with the
/// laser), [turnPage] (Space and Shift+Space, in focus mode), Ctrl/⌘+E
/// [export], Ctrl/⌘+G [goToPage], search and PDF text.
Map<ShortcutActivator, VoidCallback> editorScreenShortcuts(
  EditorSession session, {
  required VoidCallback present,
  ValueChanged<int>? turnPage,
  required EditorSearchController search,
  required VoidCallback toggleFocus,
  required VoidCallback paste,
  VoidCallback? pastePlain,
  OpenNotebooks? tabs,
  VoidCallback? closeTab,
  VoidCallback? export,
  VoidCallback? goToPage,
}) => {
  ...editorShortcuts(
    session,
    toggleFocus: toggleFocus,
    nextTab: tabs?.cycle,
    previousTab: tabs == null ? null : () => tabs.cycle(backwards: true),
    closeTab: closeTab,
    paste: paste,
    pastePlain: pastePlain,
  ),
  const SingleActivator(LogicalKeyboardKey.f5): present,
  if (export != null) ...{
    const SingleActivator(LogicalKeyboardKey.keyE, control: true): export,
    const SingleActivator(LogicalKeyboardKey.keyE, meta: true): export,
  },
  if (goToPage != null) ...{
    const SingleActivator(LogicalKeyboardKey.keyG, control: true): goToPage,
    const SingleActivator(LogicalKeyboardKey.keyG, meta: true): goToPage,
  },
  if (turnPage != null) ...{
    const SingleActivator(LogicalKeyboardKey.space): () => turnPage(1),
    const SingleActivator(LogicalKeyboardKey.space, shift: true): () => turnPage(-1),
  },
  ...EditorSearchLayer.shortcuts(search),
  ...?session.pdf == null ? null : pdfShortcuts(session.pdf!),
};
