import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../ink/tool_settings.dart';
import '../../../ink/tools/content_tools.dart';

/// Keyboard shortcuts for the lasso, shape, text and laser tools and the
/// selection. Each action goes through [unlessTyping], so none of them
/// fires while a text field has focus. [paste] replaces the in-app paste
/// (e.g. to paste images from the system clipboard too); [pastePlain]
/// (Ctrl+Shift+V) pastes text without formatting.
Map<ShortcutActivator, VoidCallback> contentShortcuts(
  ContentTools content,
  ToolSettings tools,
  VoidCallback Function(VoidCallback) unlessTyping, {
  VoidCallback? paste,
  VoidCallback? pastePlain,
}) {
  final selection = content.selection;
  void setTool(EditorTool tool) => tools.tool = tool;
  return {
    for (final (key, tool) in [
      (LogicalKeyboardKey.keyL, EditorTool.lasso),
      (LogicalKeyboardKey.keyS, EditorTool.shape),
      (LogicalKeyboardKey.keyT, EditorTool.text),
      (LogicalKeyboardKey.keyK, EditorTool.laser),
    ])
      SingleActivator(key): unlessTyping(() => setTool(tool)),
    const SingleActivator(LogicalKeyboardKey.delete): unlessTyping(selection.delete),
    const SingleActivator(LogicalKeyboardKey.backspace): unlessTyping(selection.delete),
    const SingleActivator(LogicalKeyboardKey.escape): unlessTyping(selection.clear),
    for (final control in [true, false]) ...{
      SingleActivator(LogicalKeyboardKey.keyC, control: control, meta: !control): unlessTyping(
        selection.copy,
      ),
      SingleActivator(LogicalKeyboardKey.keyX, control: control, meta: !control): unlessTyping(
        selection.cut,
      ),
      SingleActivator(LogicalKeyboardKey.keyD, control: control, meta: !control): unlessTyping(
        selection.duplicate,
      ),
      SingleActivator(LogicalKeyboardKey.keyV, control: control, meta: !control): unlessTyping(
        paste ?? content.pasteAtCentre,
      ),
      if (pastePlain != null)
        SingleActivator(LogicalKeyboardKey.keyV, control: control, meta: !control, shift: true):
            unlessTyping(pastePlain),
    },
  };
}
