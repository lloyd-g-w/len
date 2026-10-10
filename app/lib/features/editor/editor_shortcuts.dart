import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ink/tool_settings.dart';
import 'editor_session.dart';
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

/// The editor's keyboard shortcuts: undo/redo, tools, selection, page
/// turning, focus mode and tabs.
Map<ShortcutActivator, VoidCallback> editorShortcuts(
  EditorSession session, {
  required VoidCallback toggleFocus,
  VoidCallback? nextTab,
  VoidCallback? previousTab,
  VoidCallback? closeTab,
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
    ...contentShortcuts(session.content, tools, unlessTyping),
    if (session.doc case final doc?) ...{
      for (final key in [LogicalKeyboardKey.pageDown, LogicalKeyboardKey.arrowRight])
        SingleActivator(key): unlessTyping(() => doc.scrollToPage(doc.currentPage + 1)),
      for (final key in [LogicalKeyboardKey.pageUp, LogicalKeyboardKey.arrowLeft])
        SingleActivator(key): unlessTyping(() => doc.scrollToPage(doc.currentPage - 1)),
      const SingleActivator(LogicalKeyboardKey.home): unlessTyping(() => doc.scrollToPage(0)),
      const SingleActivator(LogicalKeyboardKey.end): unlessTyping(
        () => doc.scrollToPage(doc.pages.length - 1),
      ),
    },
  };
}
